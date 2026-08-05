package dev.rghello.orchestrator

import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.engine.EmbeddedServer
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.plugins.calllogging.CallLogging
import io.ktor.server.plugins.compression.Compression
import io.ktor.server.plugins.compression.gzip
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.cors.routing.CORS
import io.ktor.server.plugins.defaultheaders.DefaultHeaders
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.response.respondBytesWriter
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import io.ktor.utils.io.ByteWriteChannel
import io.ktor.utils.io.writeStringUtf8
import io.lettuce.core.RedisClient
import io.lettuce.core.api.sync.RedisCommands
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import org.apache.kafka.clients.consumer.Consumer
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerRecord
import org.apache.kafka.common.serialization.StringDeserializer
import org.apache.kafka.common.serialization.StringSerializer
import java.io.PrintStream
import java.time.Duration
import java.time.Instant
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@Serializable
data class CreateRunRequest(
    val message: String,
    val options: RunOptions? = RunOptions(),
)

@Serializable
data class RunOptions(
    val retainArtifacts: Boolean = false,
    val maximumQualityAttempts: Int = 3,
    val renderProfile: String = "DEFAULT",
)

@Serializable
data class RunResponse(
    val runId: String,
    val status: String,
    val createdAt: String,
    val links: Links,
)

@Serializable
data class Links(
    val self: String,
    val events: String,
    val stream: String,
    val artifacts: String,
)

@Serializable
data class CloudEvent(
    val specversion: String,
    val id: String,
    val source: String,
    val type: String,
    val subject: String? = null,
    val time: String? = null,
    val datacontenttype: String = "application/json",
    val correlationid: String? = null,
    val data: Map<String, String>,
)

enum class RunStatus {
    PLANNING,
    TEMP_WORKER_PENDING,
    SUCCEEDED,
    FAILED,
}

enum class RunEvent {
    PLAN_REQUESTED,
    ECHO_RECEIVED,
    FAILURE_REPORTED,
}

object RunStateMachine {
    fun transition(
        status: RunStatus,
        event: RunEvent,
    ): RunStatus =
        when (event) {
            RunEvent.PLAN_REQUESTED -> RunStatus.TEMP_WORKER_PENDING
            RunEvent.ECHO_RECEIVED ->
                if (status == RunStatus.TEMP_WORKER_PENDING) RunStatus.SUCCEEDED else status
            RunEvent.FAILURE_REPORTED -> RunStatus.FAILED
        }
}

data class RunState(
    val runId: String,
    val status: RunStatus,
    val message: String,
    val idempotencyKey: String,
    val createdAt: Instant,
)

interface EventProducer {
    fun send(
        topic: String,
        key: String,
        value: String,
    )
}

interface RunStateStore {
    fun setRunStatus(
        runId: String,
        status: RunStatus,
    )

    fun setRunResult(
        runId: String,
        result: String,
    )

    fun getRunStatus(runId: String): String?
}

class KafkaEventProducer(
    private val sendFn: (topic: String, key: String, value: String) -> Unit,
) : EventProducer {
    override fun send(
        topic: String,
        key: String,
        value: String,
    ) {
        sendFn(topic, key, value)
    }
}

class RedisRunStateStore(
    private val sync: RedisCommands<String, String>,
) : RunStateStore {
    override fun setRunStatus(
        runId: String,
        status: RunStatus,
    ) {
        sync.setex("run:$runId", STATUS_TTL_SECONDS, status.name)
    }

    override fun setRunResult(
        runId: String,
        result: String,
    ) {
        sync.setex("run:$runId:result", STATUS_TTL_SECONDS, result)
    }

    override fun getRunStatus(runId: String): String? = sync.get("run:$runId")

    private companion object {
        const val STATUS_TTL_SECONDS: Long = 3600
    }
}

fun producerProperties(bootstrap: String): Properties =
    Properties().apply {
        setProperty("bootstrap.servers", bootstrap)
        setProperty("key.serializer", StringSerializer::class.java.name)
        setProperty("value.serializer", StringSerializer::class.java.name)
        setProperty("acks", "all")
    }

fun consumerProperties(
    bootstrap: String,
    groupId: String,
): Properties =
    Properties().apply {
        setProperty("bootstrap.servers", bootstrap)
        setProperty("group.id", groupId)
        setProperty("auto.offset.reset", "earliest")
        setProperty("key.deserializer", StringDeserializer::class.java.name)
        setProperty("value.deserializer", StringDeserializer::class.java.name)
        setProperty("enable.auto.commit", "true")
    }

object Services {
    const val PLANNING_TOPIC = "rg.glyph-blueprints.v1"
    const val TEMP_ECHO_TOPIC = "rg.temp-echo.v1"
    const val RUN_EVENTS_TOPIC = "rg.run-events.v1"
    const val CONSUMER_GROUP = "run-orchestrator-m3"

    fun kafkaBootstrap(): String = System.getenv("KAFKA_BOOTSTRAP") ?: "localhost:9092"

    fun redisUrl(): String = System.getenv("REDIS_URL") ?: "redis://localhost:6379"

    fun port(): Int = (System.getenv("ORCHESTRATOR_PORT") ?: "8080").toInt()

    var eventProducer: EventProducer? = null
    var runStateStore: RunStateStore? = null
    private val consumerRunning = AtomicBoolean(false)

    fun initKafka(
        producerFactory: (String) -> EventProducer = { bootstrap ->
            val producer = KafkaProducer<String, String>(producerProperties(bootstrap))
            KafkaEventProducer { topic, key, value -> producer.send(ProducerRecord(topic, key, value)) }
        },
    ) {
        eventProducer = producerFactory(kafkaBootstrap())
    }

    fun initRedis(
        storeFactory: (String) -> RunStateStore = { redisUrl ->
            RedisRunStateStore(RedisClient.create(redisUrl).connect().sync())
        },
    ) {
        runStateStore = storeFactory(redisUrl())
    }

    fun startConsumer(consumerFactory: (Properties) -> Consumer<String, String> = { KafkaConsumer(it) }) {
        if (consumerRunning.compareAndSet(false, true)) {
            val consumer = consumerFactory(consumerProperties(kafkaBootstrap(), CONSUMER_GROUP))
            consumer.subscribe(listOf(TEMP_ECHO_TOPIC))
            Executors.newSingleThreadExecutor().submit {
                consumeLoop(consumer)
            }
        }
    }

    fun consumeLoop(consumer: Consumer<String, String>) {
        try {
            while (!Thread.currentThread().isInterrupted) {
                val records = consumer.poll(Duration.ofMillis(500))
                for (record in records) {
                    handleEchoResponse(record.key(), record.value())
                }
            }
        } catch (e: Exception) {
            System.err.println("Kafka consumer error: ${e.message}")
        } finally {
            consumer.close()
        }
    }
}

val runs: ConcurrentHashMap<String, RunState> = ConcurrentHashMap()
val idempotentRuns: ConcurrentHashMap<String, String> = ConcurrentHashMap()
val sseClients: ConcurrentHashMap<String, CopyOnWriteArrayList<SseClient>> = ConcurrentHashMap()
val lastRunEvents: ConcurrentHashMap<String, String> = ConcurrentHashMap()

data class SseClient(
    val channel: Channel<String>,
)

var exit: (Int) -> Unit = { code -> kotlin.system.exitProcess(code) }

fun main(args: Array<String>) {
    exit(run(System.out, System.err, args))
}

fun run(
    stdout: PrintStream,
    stderr: PrintStream,
    args: Array<String>,
): Int {
    if (args.isNotEmpty() && args[0] == "version") {
        stdout.println("${Version.SERVICE_NAME} ${Version.VERSION}")
        return 0
    }
    return runServer(stdout, stderr)
}

fun runServer(
    stdout: PrintStream,
    stderr: PrintStream,
): Int {
    System.setOut(stdout)
    System.setErr(stderr)
    Services.initKafka()
    Services.initRedis()
    Services.startConsumer()

    buildServer(Services.port()).start(wait = true)
    return 0
}

fun buildServer(port: Int): EmbeddedServer<*, *> =
    embeddedServer(Netty, port = port, host = "0.0.0.0") {
        module()
    }

fun Application.module() {
    install(ContentNegotiation) {
        json(
            Json {
                ignoreUnknownKeys = true
                encodeDefaults = true
            },
        )
    }
    install(DefaultHeaders)
    install(CallLogging)
    install(CORS) {
        anyHost()
    }
    install(Compression) {
        gzip()
    }
    install(StatusPages) {
        exception<Throwable> { call, cause ->
            System.err.println("Unhandled error: ${cause.message}")
            call.respond(HttpStatusCode.InternalServerError)
        }
    }
    routing {
        route("api/v1") {
            route("runs") {
                post { handleCreateRun(call) }
                route("{runId}") {
                    get { handleGetRun(call) }
                    route("stream") {
                        get { handleSseStream(call) }
                    }
                    route("artifacts") {
                        get { handleListArtifacts(call) }
                    }
                    post("cancel") { handleCancelRun(call) }
                }
            }
        }
        get("healthz") {
            call.respond(HttpStatusCode.OK, "OK")
        }
    }
}

suspend fun handleCreateRun(call: ApplicationCall) {
    val request = call.receive<CreateRunRequest>()
    val idempotencyKey = call.request.headers["Idempotency-Key"] ?: UUID.randomUUID().toString()

    val cachedRunId = idempotentRuns[idempotencyKey]
    if (cachedRunId != null) {
        call.respond(
            HttpStatusCode.Conflict,
            RunResponse(
                runId = cachedRunId,
                status = "PLANNING",
                createdAt = Instant.now().toString(),
                links = buildLinks(cachedRunId),
            ),
        )
        return
    }

    val runId = UUID.randomUUID().toString()
    val runState =
        RunState(
            runId = runId,
            status = RunStatus.PLANNING,
            message = request.message,
            idempotencyKey = idempotencyKey,
            createdAt = Instant.now(),
        )
    idempotentRuns[idempotencyKey] = runId
    runs[runId] = runState

    Services.runStateStore?.setRunStatus(runId, runState.status)

    broadcastEvent(runId, eventMap("PLANNING", "Run created and planning started"))

    val event =
        CloudEvent(
            specversion = "1.0",
            id = UUID.randomUUID().toString(),
            source = "run-orchestrator",
            type = Services.PLANNING_TOPIC,
            subject = "runs/$runId",
            time = runState.createdAt.toString(),
            correlationid = runId,
            data =
                mapOf(
                    "runId" to runId,
                    "stepId" to UUID.randomUUID().toString(),
                    "message" to request.message,
                    "attempt" to "1",
                    "inputMaturity" to "10",
                    "outputMaturity" to "20",
                    "transformation" to "plan-glyphs",
                    "transformVersion" to "0.1.0-temporary",
                ),
        )

    val producer = Services.eventProducer
    if (producer != null) {
        val json = Json { encodeDefaults = true }
        val eventJson = json.encodeToString(CloudEvent.serializer(), event)
        producer.send(Services.PLANNING_TOPIC, runId, eventJson)
        val pending = runs[runId]?.copy(status = RunStateMachine.transition(runState.status, RunEvent.PLAN_REQUESTED))
        if (pending != null) {
            runs[runId] = pending
            Services.runStateStore?.setRunStatus(runId, pending.status)
        }
        broadcastEvent(runId, eventMap("TEMP_WORKER_PENDING", "Waiting for temporary worker"))
    }

    call.respond(
        HttpStatusCode.Accepted,
        RunResponse(
            runId = runId,
            status = RunStatus.PLANNING.name,
            createdAt = runState.createdAt.toString(),
            links = buildLinks(runId),
        ),
    )
}

suspend fun handleGetRun(call: ApplicationCall) {
    val runId =
        call.parameters["runId"] ?: run {
            call.respond(HttpStatusCode.BadRequest, "Missing runId")
            return
        }
    val status = Services.runStateStore?.getRunStatus(runId) ?: runs[runId]?.status?.name ?: "UNKNOWN"
    call.respond(mapOf("runId" to runId, "status" to status))
}

suspend fun handleSseStream(call: ApplicationCall) {
    val runId =
        call.parameters["runId"] ?: run {
            call.respond(HttpStatusCode.BadRequest, "Missing runId")
            return
        }

    val channel = Channel<String>(Channel.BUFFERED)
    val client = SseClient(channel)
    sseClients.getOrPut(runId) { CopyOnWriteArrayList() }.add(client)

    try {
        call.respondBytesWriter(ContentType.Text.EventStream, HttpStatusCode.OK) {
            writeSseLoop(channel, lastRunEvents[runId])
        }
    } finally {
        sseClients[runId]?.remove(client)
        channel.cancel()
    }
}

suspend fun ByteWriteChannel.writeSseLoop(
    channel: Channel<String>,
    replayEvent: String? = null,
) {
    writeStringUtf8(": connected\n\n")
    flush()
    if (replayEvent != null) {
        writeStringUtf8("data: $replayEvent\n\n")
        flush()
    }
    while (true) {
        val msg = channel.receive()
        writeStringUtf8("data: $msg\n\n")
        flush()
    }
}

suspend fun handleListArtifacts(call: ApplicationCall) {
    call.respond(mapOf("artifacts" to emptyList<Map<String, String>>()))
}

suspend fun handleCancelRun(call: ApplicationCall) {
    val runId =
        call.parameters["runId"] ?: run {
            call.respond(HttpStatusCode.BadRequest, "Missing runId")
            return
        }
    call.respond(mapOf("runId" to runId, "status" to "CANCEL_REQUESTED"))
}

fun buildLinks(runId: String): Links =
    Links(
        self = "/api/v1/runs/$runId",
        events = "/api/v1/runs/$runId/events",
        stream = "/api/v1/runs/$runId/stream",
        artifacts = "/api/v1/runs/$runId/artifacts",
    )

fun broadcastEvent(
    runId: String,
    data: Map<String, String>,
) {
    val eventData =
        buildJsonObject {
            data.forEach { (key, value) -> put(key, JsonPrimitive(value)) }
        }.toString()
    lastRunEvents[runId] = eventData
    val clients = sseClients[runId]?.toList() ?: return
    for (client in clients) {
        client.channel.trySend(eventData)
    }
}

fun handleEchoResponse(
    runId: String?,
    message: String,
) {
    val json = Json { ignoreUnknownKeys = true }
    val id = runId ?: return
    try {
        val event = json.decodeFromString(CloudEvent.serializer(), message)
        val state = runs[id]
        if (state != null) {
            val succeeded =
                state.copy(
                    status = RunStateMachine.transition(state.status, RunEvent.ECHO_RECEIVED),
                )
            runs[id] = succeeded
            val assembledText = event.data["assembledText"] ?: event.data["message"] ?: ""
            Services.runStateStore?.setRunResult(id, assembledText)
            Services.runStateStore?.setRunStatus(id, succeeded.status)
            broadcastEvent(
                id,
                mapOf(
                    "status" to "SUCCEEDED",
                    "message" to "Run completed",
                    "assembledText" to assembledText,
                    "timestamp" to Instant.now().toString(),
                ),
            )

            val finalEvent =
                CloudEvent(
                    specversion = "1.0",
                    id = UUID.randomUUID().toString(),
                    source = "run-orchestrator",
                    type = Services.RUN_EVENTS_TOPIC,
                    subject = "runs/$id",
                    time = Instant.now().toString(),
                    correlationid = id,
                    data =
                        mapOf(
                            "runId" to id,
                            "status" to "SUCCEEDED",
                            "assembledText" to assembledText,
                        ),
                )
            val eventJson = json.encodeToString(CloudEvent.serializer(), finalEvent)
            Services.eventProducer?.send(Services.RUN_EVENTS_TOPIC, id, eventJson)
        }
    } catch (e: Exception) {
        System.err.println("Error parsing echo response: ${e.message}")
    }
}

fun eventMap(
    status: String,
    message: String,
): Map<String, String> =
    mapOf(
        "status" to status,
        "message" to message,
        "timestamp" to Instant.now().toString(),
    )
