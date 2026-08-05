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
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.apache.kafka.clients.consumer.KafkaConsumer
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerRecord
import org.apache.kafka.common.serialization.StringDeserializer
import org.apache.kafka.common.serialization.StringSerializer
import java.io.PrintStream
import java.nio.CharBuffer
import java.nio.charset.CharacterCodingException
import java.time.Instant
import java.util.Properties
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

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
    val data: Map<String, JsonElement>,
)

enum class RunStatus {
    PLANNING,
    GENERATING_GEOMETRY,
    NORMALIZING,
    SUCCEEDED,
    FAILED,
}

enum class RunEvent {
    PLANNED,
    GEOMETRY_COMPLETE,
    NORMALIZED_COMPLETE,
    FAILURE_REPORTED,
}

object RunStateMachine {
    fun transition(
        status: RunStatus,
        event: RunEvent,
    ): RunStatus =
        when (event) {
            RunEvent.PLANNED -> {
                if (status == RunStatus.PLANNING) RunStatus.GENERATING_GEOMETRY else status
            }

            RunEvent.GEOMETRY_COMPLETE -> {
                if (status == RunStatus.GENERATING_GEOMETRY) RunStatus.NORMALIZING else status
            }

            RunEvent.NORMALIZED_COMPLETE -> {
                if (status == RunStatus.NORMALIZING) RunStatus.SUCCEEDED else status
            }

            RunEvent.FAILURE_REPORTED -> {
                RunStatus.FAILED
            }
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

object Services {
    const val PLANNING_TOPIC = "rg.glyph-blueprints.v1"
    const val GEOMETRY_TOPIC = "rg.geometry-expanded.v1"
    const val NORMALIZED_TOPIC = "rg.glyph-normalized.v1"
    const val RUN_EVENTS_TOPIC = "rg.run-events.v1"
    const val ALPHABET = "RUBE_SIMPLEX_V1"

    fun kafkaBootstrap(): String = System.getenv("KAFKA_BOOTSTRAP") ?: "localhost:9092"

    fun redisUrl(): String = System.getenv("REDIS_URL") ?: "redis://localhost:6379"

    fun glyphCatalogUrl(): String = System.getenv("GLYPH_CATALOG_URL") ?: "http://localhost:8082/ws/glyph-catalog"

    fun port(): Int = (System.getenv("ORCHESTRATOR_PORT") ?: "8080").toInt()

    var eventProducer: EventProducer? = null
    var runStateStore: RunStateStore? = null
    var planner: GlyphPlanner? = null
    var stageMonitor: StageMonitor? = null

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

    fun initStageMonitor(monitorFactory: () -> StageMonitor = { StageMonitor(StageProgressTracker(), StageEventValidator()) }) {
        stageMonitor = monitorFactory()
    }
}

val runs: ConcurrentHashMap<String, RunState> = ConcurrentHashMap()
val idempotentRuns: ConcurrentHashMap<String, String> = ConcurrentHashMap()
val expectedTexts: ConcurrentHashMap<String, String> = ConcurrentHashMap()
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
    Services.initStageMonitor()
    Services.planner = GlyphCatalogClient(Services.glyphCatalogUrl())

    startStageConsumer()

    buildServer(Services.port()).start(wait = true)
    return 0
}

fun startStageConsumer() {
    val monitor = Services.stageMonitor ?: return
    val consumer =
        try {
            KafkaConsumer<String, String>(consumerProperties(Services.kafkaBootstrap()))
        } catch (e: Exception) {
            System.err.println("stage consumer init failed: ${e.message}")
            return
        }
    consumer.subscribe(listOf(Services.GEOMETRY_TOPIC, Services.NORMALIZED_TOPIC))
    val thread = Thread { StageConsumer(consumer, monitor).runForever() }
    thread.isDaemon = true
    thread.name = "stage-consumer"
    thread.start()
}

fun consumerProperties(bootstrap: String): Properties =
    Properties().apply {
        setProperty("bootstrap.servers", bootstrap)
        setProperty("key.deserializer", StringDeserializer::class.java.name)
        setProperty("value.deserializer", StringDeserializer::class.java.name)
        setProperty("group.id", "run-orchestrator")
        setProperty("auto.offset.reset", "earliest")
        setProperty("enable.auto.commit", "true")
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

    if (!isValidUtf8(request.message)) {
        call.respond(HttpStatusCode.BadRequest, mapOf("error" to "message is not valid UTF-8"))
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

    val planner = Services.planner
    if (planner == null) {
        failRun(runId, "glyph planner not configured")
        call.respond(HttpStatusCode.InternalServerError, mapOf("runId" to runId, "status" to "FAILED"))
        return
    }

    val plan =
        try {
            planner.plan(request.message, Services.ALPHABET, "PRIMARY")
        } catch (e: Exception) {
            System.err.println("SOAP planning failed: ${e.message}")
            failRun(runId, "SOAP planning failed: ${e.message}")
            call.respond(
                HttpStatusCode.InternalServerError,
                mapOf("runId" to runId, "status" to "FAILED", "error" to (e.message ?: "planning failed")),
            )
            return
        }

    expectedTexts[runId] = request.message

    val producer = Services.eventProducer
    if (producer != null) {
        val stepId = UUID.randomUUID().toString()
        val json = Json { encodeDefaults = true }
        for (glyph in plan.glyphs) {
            val event =
                CloudEvent(
                    specversion = "1.0",
                    id = UUID.randomUUID().toString(),
                    source = "run-orchestrator",
                    type = Services.PLANNING_TOPIC,
                    subject = "runs/$runId",
                    time = Instant.now().toString(),
                    correlationid = runId,
                    data = blueprintEventData(runId, plan.planId, stepId, glyph),
                )
            producer.send(
                Services.PLANNING_TOPIC,
                "$runId:${glyph.glyphInstanceId}",
                json.encodeToString(CloudEvent.serializer(), event),
            )
        }
        broadcastEvent(runId, eventMap("PLANNED", "SOAP plan produced ${plan.glyphs.size} glyph blueprints"))
        Services.stageMonitor?.registerRun(runId, plan.glyphs.size)
        transitionRun(runId, RunEvent.PLANNED)
    }

    call.respond(
        HttpStatusCode.Accepted,
        RunResponse(
            runId = runId,
            status = runs[runId]?.status?.name ?: RunStatus.GENERATING_GEOMETRY.name,
            createdAt = runState.createdAt.toString(),
            links = buildLinks(runId),
        ),
    )
}

fun transitionRun(
    runId: String,
    event: RunEvent,
) {
    val state = runs[runId] ?: return
    val next = RunStateMachine.transition(state.status, event)
    if (next == state.status) {
        return
    }
    runs[runId] = state.copy(status = next)
    Services.runStateStore?.setRunStatus(runId, next)
    broadcastEvent(runId, eventMap(next.name, "Run moved to ${next.name}"))
}

fun completeRun(
    runId: String,
    assembledText: String,
) {
    val state = runs[runId] ?: return
    val succeeded = state.copy(status = RunStateMachine.transition(state.status, RunEvent.NORMALIZED_COMPLETE))
    if (succeeded.status == state.status) {
        return
    }
    runs[runId] = succeeded
    Services.runStateStore?.setRunResult(runId, assembledText)
    Services.runStateStore?.setRunStatus(runId, succeeded.status)
    broadcastEvent(
        runId,
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
            subject = "runs/$runId",
            time = Instant.now().toString(),
            correlationid = runId,
            data =
                mapOf(
                    "runId" to JsonPrimitive(runId),
                    "status" to JsonPrimitive("SUCCEEDED"),
                    "assembledText" to JsonPrimitive(assembledText),
                ),
        )
    val json = Json { encodeDefaults = true }
    Services.eventProducer?.send(Services.RUN_EVENTS_TOPIC, runId, json.encodeToString(CloudEvent.serializer(), finalEvent))
}

fun failRun(
    runId: String,
    reason: String,
) {
    val state = runs[runId] ?: return
    runs[runId] = state.copy(status = RunStateMachine.transition(state.status, RunEvent.FAILURE_REPORTED))
    Services.runStateStore?.setRunStatus(runId, RunStatus.FAILED)
    broadcastEvent(runId, eventMap("FAILED", reason))
}

fun blueprintEventData(
    runId: String,
    planId: String,
    stepId: String,
    glyph: SoapGlyph,
): Map<String, JsonElement> =
    buildJsonObject {
        put("runId", JsonPrimitive(runId))
        put("planId", JsonPrimitive(planId))
        put("stepId", JsonPrimitive(stepId))
        put("attempt", JsonPrimitive(1))
        put("inputArtifacts", JsonArray(emptyList()))
        put("outputArtifacts", JsonArray(emptyList()))
        put(
            "transformation",
            buildJsonObject {
                put("name", JsonPrimitive("plan-glyphs"))
                put("version", JsonPrimitive("1.0.0"))
            },
        )
        put(
            "glyphs",
            JsonArray(
                listOf(
                    buildJsonObject {
                        put("glyphInstanceId", JsonPrimitive(glyph.glyphInstanceId))
                        put("position", JsonPrimitive(glyph.position))
                        put("kind", JsonPrimitive(glyph.kind))
                        put("advanceWidth", JsonPrimitive(glyph.advanceWidth))
                        put(
                            "primitives",
                            JsonArray(
                                glyph.primitives.map { primitive ->
                                    buildJsonObject {
                                        put("type", JsonPrimitive(primitive.type))
                                        put(
                                            "points",
                                            JsonArray(
                                                primitive.points.map { point ->
                                                    buildJsonObject {
                                                        put("x", JsonPrimitive(point.x))
                                                        put("y", JsonPrimitive(point.y))
                                                    }
                                                },
                                            ),
                                        )
                                    }
                                },
                            ),
                        )
                    },
                ),
            ),
        )
    }

fun isValidUtf8(value: String): Boolean =
    try {
        Charsets.UTF_8.newEncoder().encode(CharBuffer.wrap(value))
        true
    } catch (e: CharacterCodingException) {
        false
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

fun eventMap(
    status: String,
    message: String,
): Map<String, String> =
    mapOf(
        "status" to status,
        "message" to message,
        "timestamp" to Instant.now().toString(),
    )
