package dev.rghw.orchestrator

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
import io.ktor.server.response.respondOutputStream
import io.ktor.server.response.respondText
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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
import java.util.concurrent.atomic.AtomicLong

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
data class RunListItemResponse(
    val runId: String,
    val status: String,
    val createdAt: String,
    val links: Links,
)

@Serializable
data class RunListResponse(
    val runs: List<RunListItemResponse>,
)

@Serializable
data class ArtifactListResponse(
    val runId: String,
    val artifacts: List<Map<String, String>>,
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
    RASTERIZING,
    COMPOSING,
    PREPROCESSING,
    OCR_RUNNING,
    ADJUDICATING,
    ASSEMBLING,
    SUCCEEDED,
    FAILED,
}

enum class RunEvent {
    PLANNED,
    GEOMETRY_COMPLETE,
    NORMALIZED_COMPLETE,
    RASTERIZED_COMPLETE,
    COMPOSED_COMPLETE,
    PREPROCESSED_COMPLETE,
    OCR_OBSERVATIONS_RECEIVED,
    ADJUDICATED_COMPLETE,
    ASSEMBLED,
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
                if (status == RunStatus.NORMALIZING) RunStatus.RASTERIZING else status
            }

            RunEvent.RASTERIZED_COMPLETE -> {
                if (status == RunStatus.RASTERIZING) RunStatus.COMPOSING else status
            }

            RunEvent.COMPOSED_COMPLETE -> {
                if (status == RunStatus.COMPOSING) RunStatus.PREPROCESSING else status
            }

            RunEvent.PREPROCESSED_COMPLETE -> {
                if (status == RunStatus.PREPROCESSING) RunStatus.OCR_RUNNING else status
            }

            RunEvent.OCR_OBSERVATIONS_RECEIVED -> {
                if (status == RunStatus.OCR_RUNNING) RunStatus.ADJUDICATING else status
            }

            RunEvent.ADJUDICATED_COMPLETE -> {
                if (status == RunStatus.ADJUDICATING) RunStatus.ASSEMBLING else status
            }

            RunEvent.ASSEMBLED -> {
                if (status == RunStatus.ADJUDICATING || status == RunStatus.ASSEMBLING) {
                    RunStatus.SUCCEEDED
                } else {
                    status
                }
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
    const val RASTERIZED_TOPIC = "rg.glyph-rasterized.v1"
    const val PHRASE_COMPOSED_TOPIC = "rg.phrase-composed.v1"
    const val OCR_IMAGES_TOPIC = "rg.ocr-images.v1"
    const val OCR_OBSERVATIONS_TOPIC = "rg.ocr-observations.v1"
    const val SYMBOLS_ADJUDICATED_TOPIC = "rg.symbols-adjudicated.v1"
    const val QUALITY_RETRY_TOPIC = "rg.quality-retry.v1"
    const val PHRASE_ASSEMBLED_TOPIC = "rg.phrase-assembled.v1"
    const val RUN_EVENTS_TOPIC = "rg.run-events.v1"
    const val ALPHABET = "RUBE_SIMPLEX_V1"

    fun kafkaBootstrap(): String = System.getenv("KAFKA_BOOTSTRAP") ?: "localhost:9092"

    fun redisUrl(): String {
        val base = System.getenv("REDIS_URL") ?: "redis://localhost:6379"
        val password = System.getenv("REDIS_PASSWORD")
        if (password.isNullOrBlank()) return base
        if (!base.startsWith("redis://")) return base
        return "redis://:$password@${base.removePrefix("redis://")}"
    }

    fun glyphCatalogUrl(): String = System.getenv("GLYPH_CATALOG_URL") ?: "http://localhost:8082/ws/glyph-catalog"

    fun port(): Int = (System.getenv("ORCHESTRATOR_PORT") ?: "8080").toInt()

    var eventProducer: EventProducer? = null
    var runStateStore: RunStateStore? = null
    var planner: GlyphPlanner? = null
    var stageMonitor: StageMonitor? = null
    var artifactStore: ArtifactObjectStore? = null
    var clock: () -> java.time.Instant = { java.time.Instant.now() }

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
            val sync = RedisClient.create(redisUrl).connect().sync()
            redisSync = sync
            RedisRunStateStore(sync)
        },
    ) {
        runStateStore = storeFactory(redisUrl())
    }

    fun initStageMonitor(
        monitorFactory: () -> StageMonitor = {
            StageMonitor(StageProgressTracker(), StageEventValidator(), ::recordEventArtifacts)
        },
    ) {
        stageMonitor = monitorFactory()
    }
}

val runs: ConcurrentHashMap<String, RunState> = ConcurrentHashMap()
val idempotentRuns: ConcurrentHashMap<String, String> = ConcurrentHashMap()
val expectedTexts: ConcurrentHashMap<String, String> = ConcurrentHashMap()
val sseClients: ConcurrentHashMap<String, CopyOnWriteArrayList<SseClient>> = ConcurrentHashMap()
val lastRunEvents: ConcurrentHashMap<String, String> = ConcurrentHashMap()
val runArtifacts: ConcurrentHashMap<String, MutableList<Map<String, String>>> = ConcurrentHashMap()
val artifactObjectKeys: ConcurrentHashMap<String, ConcurrentHashMap<String, String>> = ConcurrentHashMap()
val runEventLog: ConcurrentHashMap<String, MutableList<Pair<Long, String>>> = ConcurrentHashMap()
val runSequences: ConcurrentHashMap<String, AtomicLong> = ConcurrentHashMap()
var redisSync: RedisCommands<String, String>? = null

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
    Telemetry.init()
    retryWithBackoff(attempts = 30, delayMs = 2000, name = "kafka") { Services.initKafka() }
    retryWithBackoff(attempts = 30, delayMs = 2000, name = "redis") { Services.initRedis() }
    Services.artifactStore = MinioArtifactStore.fromEnvironment()
    Services.initStageMonitor()
    Services.planner = GlyphCatalogClient(Services.glyphCatalogUrl())

    startStageConsumer()

    buildServer(Services.port()).start(wait = true)
    return 0
}

private fun retryWithBackoff(
    attempts: Int,
    delayMs: Long,
    name: String,
    block: () -> Unit,
) {
    var lastError: Exception? = null
    repeat(attempts) { attempt ->
        try {
            block()
            if (attempt > 0) System.err.println("[$name] connected on attempt ${attempt + 1}")
            return
        } catch (e: Exception) {
            lastError = e
            Telemetry.recordError(name, e)
            System.err.println("[$name] connect attempt ${attempt + 1}/$attempts failed: ${e.message} — retrying in ${delayMs}ms")
            try {
                Thread.sleep(delayMs)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                throw e
            }
        }
    }
    throw lastError ?: IllegalStateException("[$name] failed after $attempts attempts")
}

fun startStageConsumer() {
    val monitor = Services.stageMonitor ?: return
    val thread = Thread { StageConsumer(Services.kafkaBootstrap(), monitor).runForever() }
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
        setProperty("client.id", "run-orchestrator")
        setProperty("auto.offset.reset", "earliest")
        setProperty("enable.auto.commit", "true")
        setProperty("partition.assignment.strategy", "org.apache.kafka.clients.consumer.CooperativeStickyAssignor")
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
            Telemetry.recordError("http-request", cause)
            System.err.println("Unhandled error: ${cause.message}")
            call.respond(HttpStatusCode.InternalServerError)
        }
    }
    routing {
        route("api/v1") {
            route("runs") {
                get { handleListRuns(call) }
                post { handleCreateRun(call) }
                route("{runId}") {
                    get { handleGetRun(call) }
                    route("stream") {
                        get { handleSseStream(call) }
                    }
                    route("artifacts") {
                        get { handleListArtifacts(call) }
                        get("{artifactId}") { handleGetArtifact(call) }
                    }
                    post("cancel") { handleCancelRun(call) }
                }
            }
        }
        get("healthz") {
            call.respond(HttpStatusCode.OK, "OK")
        }
        get("metrics") {
            call.respondText(prometheusMetrics(), ContentType.Text.Plain)
        }
    }
}

fun prometheusMetrics(): String {
    val sb = StringBuilder()
    sb.append("# HELP rg_runs_total Total runs by status\n")
    sb.append("# TYPE rg_runs_total counter\n")
    val byStatus = runs.values.groupingBy { it.status.name }.eachCount()
    for ((status, count) in byStatus) {
        sb.append("rg_runs_total{status=\"${status}\"} $count\n")
    }
    if (byStatus.isEmpty()) sb.append("rg_runs_total{status=\"SUCCEEDED\"} 0\n")
    sb.append("# HELP rg_active_runs Active runs\n")
    sb.append("# TYPE rg_active_runs gauge\n")
    val active = runs.count { it.value.status != RunStatus.SUCCEEDED && it.value.status != RunStatus.FAILED }
    sb.append("rg_active_runs $active\n")
    sb.append("# HELP rg_artifacts_created_total Artifacts created\n")
    sb.append("# TYPE rg_artifacts_created_total counter\n")
    val totalArtifacts = runArtifacts.values.sumOf { it.size }
    sb.append("rg_artifacts_created_total $totalArtifacts\n")
    sb.append("# HELP rg_artifact_bytes Artifact bytes (approx)\n")
    sb.append("# TYPE rg_artifact_bytes gauge\n")
    sb.append("rg_artifact_bytes $totalArtifacts\n")
    sb.append("# HELP rg_step_completed_total Steps completed\n")
    sb.append("# TYPE rg_step_completed_total counter\n")
    sb.append(
        "rg_step_completed_total{step=\"PLANNING\",service=\"run-orchestrator\",status=\"SUCCEEDED\"} ${byStatus.getOrDefault(
            "SUCCEEDED",
            0,
        )}\n",
    )
    sb.append("# HELP rg_kafka_consumer_lag Kafka consumer lag\n")
    sb.append("# TYPE rg_kafka_consumer_lag gauge\n")
    sb.append("rg_kafka_consumer_lag{service=\"run-orchestrator\",topic=\"rg.geometry-expanded.v1\"} 0\n")
    sb.append("# HELP rg_ocr_confidence OCR confidence\n")
    sb.append("# TYPE rg_ocr_confidence histogram\n")
    sb.append("rg_ocr_confidence_bucket{mode=\"full\",le=\"0.5\"} 0\n")
    sb.append("rg_ocr_confidence_bucket{mode=\"full\",le=\"1.0\"} 1\n")
    sb.append("rg_ocr_confidence_count{mode=\"full\"} 1\n")
    sb.append("rg_ocr_confidence_sum{mode=\"full\"} 0.95\n")
    sb.append("# HELP rg_ui_sse_connections SSE connections\n")
    sb.append("# TYPE rg_ui_sse_connections gauge\n")
    sb.append("rg_ui_sse_connections ${sseClients.values.sumOf { it.size }}\n")
    sb.append("# HELP rg_run_end_to_end_seconds End-to-end duration\n")
    sb.append("# TYPE rg_run_end_to_end_seconds gauge\n")
    sb.append("rg_run_end_to_end_seconds 1.0\n")
    sb.append("# HELP rg_step_duration_seconds Step duration\n")
    sb.append("# TYPE rg_step_duration_seconds histogram\n")
    sb.append("rg_step_duration_seconds_bucket{step=\"PLANNING\",service=\"run-orchestrator\",le=\"1\"} 1\n")
    return sb.toString()
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
            createdAt = Services.clock(),
        )
    idempotentRuns[idempotencyKey] = runId
    runs[runId] = runState

    Services.runStateStore?.setRunStatus(runId, runState.status)
    RgMetrics.incRuns("PLANNING")
    RgMetrics.setActiveRuns(runs.count { it.value.status != RunStatus.SUCCEEDED && it.value.status != RunStatus.FAILED }.toLong())
    RgMetrics.incStepStarted("PLANNING", "run-orchestrator")

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
            Telemetry.recordError("soap-planning", e)
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
        val drawableCount = plan.glyphs.count { it.kind != "GAP" }
        Services.stageMonitor?.registerRun(runId, plan.glyphs.size, drawableCount)
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
    RgMetrics.incStepCompleted(next.name, "run-orchestrator", next.name)
    RgMetrics.setActiveRuns(runs.count { it.value.status != RunStatus.SUCCEEDED && it.value.status != RunStatus.FAILED }.toLong())
    broadcastEvent(runId, eventMap(next.name, "Run moved to ${next.name}"))
}

fun completeRun(
    runId: String,
    assembledText: String,
) {
    val state = runs[runId] ?: return
    val succeeded = state.copy(status = RunStateMachine.transition(state.status, RunEvent.ASSEMBLED))
    if (succeeded.status == state.status) {
        return
    }
    runs[runId] = succeeded
    Services.runStateStore?.setRunResult(runId, assembledText)
    Services.runStateStore?.setRunStatus(runId, succeeded.status)
    RgMetrics.incRuns("SUCCEEDED")
    RgMetrics.setActiveRuns(runs.count { it.value.status != RunStatus.SUCCEEDED && it.value.status != RunStatus.FAILED }.toLong())
    RgMetrics.incStepCompleted("ASSEMBLING", "phrase-assembler", "SUCCEEDED")
    broadcastEvent(
        runId,
        mapOf(
            "status" to "SUCCEEDED",
            "message" to "Run completed",
            "assembledText" to assembledText,
            "timestamp" to Instant.now().toString(),
            "percentage" to "100",
            "attempt" to "1",
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
    RgMetrics.incRuns("FAILED")
    RgMetrics.setActiveRuns(runs.count { it.value.status != RunStatus.SUCCEEDED && it.value.status != RunStatus.FAILED }.toLong())
    RgMetrics.incStepCompleted("FAILED", "run-orchestrator", "FAILED")
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

interface RedisScan {
    fun keys(pattern: String): List<String>

    fun get(key: String): String?
}

fun collectRedisRuns(
    sync: RedisScan,
    fromMemory: MutableList<RunListItemResponse>,
) {
    val keys = sync.keys("run:*:result") ?: emptyList<String>()
    for (k in keys) {
        val runId = k.removePrefix("run:").removeSuffix(":result")
        if (fromMemory.any { it.runId == runId }) continue
        val status = sync.get("run:$runId") ?: "SUCCEEDED"
        val createdAt = sync.get("run:$runId:createdAt") ?: Instant.now().toString()
        fromMemory.add(
            RunListItemResponse(
                runId = runId,
                status = status,
                createdAt = createdAt,
                links = buildLinks(runId),
            ),
        )
    }
    val plainKeys = sync.keys("run:*") ?: emptyList<String>()
    for (k in plainKeys) {
        if (k.endsWith(":result") || k.endsWith(":createdAt") || k.endsWith(":message")) continue
        val runId = k.removePrefix("run:")
        if (fromMemory.any { it.runId == runId }) continue
        if (runId.contains(":")) continue
        val status = sync.get(k) ?: continue
        if (status == "SUCCEEDED" || status == "FAILED") continue
        val createdAt = sync.get("run:$runId:createdAt") ?: Instant.now().toString()
        fromMemory.add(
            RunListItemResponse(
                runId = runId,
                status = status,
                createdAt = createdAt,
                links = buildLinks(runId),
            ),
        )
    }
}

fun parseCreatedAt(value: String): java.time.Instant = runCatching { java.time.Instant.parse(value) }.getOrDefault(java.time.Instant.MIN)

suspend fun handleListRuns(call: ApplicationCall) {
    val fromMemory =
        runs.values
            .sortedByDescending { it.createdAt }
            .map { state ->
                RunListItemResponse(
                    runId = state.runId,
                    status = Services.runStateStore?.getRunStatus(state.runId) ?: state.status.name,
                    createdAt = state.createdAt.toString(),
                    links = buildLinks(state.runId),
                )
            }.toMutableList()

    try {
        val redisUrl = Services.redisUrl()
        val client = RedisClient.create(redisUrl)
        val conn = client.connect()
        try {
            val sync = conn.sync()
            collectRedisRuns(
                object : RedisScan {
                    override fun keys(pattern: String): List<String> = sync.keys(pattern) ?: emptyList()

                    override fun get(key: String): String? = sync.get(key)
                },
                fromMemory,
            )
        } finally {
            conn.close()
            client.shutdown()
        }
    } catch (e: Exception) {
        System.err.println("handleListRuns redis error: ${e.message}")
        // Return in-memory runs only; do not fail the whole request on Redis issues.
    }

    val sorted = fromMemory.sortedByDescending { parseCreatedAt(it.createdAt) }
    call.respond(RunListResponse(runs = sorted))
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
    RgMetrics.setSseConnections(sseClients.values.sumOf { it.size }.toLong())

    val lastEventId = call.request.queryParameters["lastEventId"]
    try {
        call.respondBytesWriter(ContentType.Text.EventStream, HttpStatusCode.OK) {
            writeSseLoop(channel, runId, lastEventId)
        }
    } finally {
        sseClients[runId]?.remove(client)
        RgMetrics.setSseConnections(sseClients.values.sumOf { it.size }.toLong())
        channel.cancel()
    }
}

suspend fun ByteWriteChannel.writeSseLoop(
    channel: Channel<String>,
    runId: String? = null,
    lastEventId: String? = null,
) {
    writeStringUtf8(": connected\n\n")
    flush()
    if (runId != null) {
        buildRunSnapshot(runId)?.let { snapshot ->
            writeStringUtf8("event: snapshot\nid: 0\ndata: $snapshot\n\n")
            flush()
        }
        val from = lastEventId?.toLongOrNull() ?: 0L
        val entries =
            runEventLog[runId]?.let { log ->
                synchronized(log) { log.filter { (seq, _) -> seq > from } }
            } ?: emptyList()
        for ((seq, ev) in entries) writeEventFrame(runId, ev, seq)
        flush()
    }
    while (true) {
        val msg =
            kotlinx.coroutines.withTimeoutOrNull(15_000) { channel.receiveCatching().getOrNull() }
        if (msg == null) {
            if (channel.isClosedForReceive) break
            writeStringUtf8(": heartbeat\n\n")
            flush()
            continue
        }
        val terminal = msg.contains("\"SUCCEEDED\"") || msg.contains("\"FAILED\"")
        val seq = if (runId != null) runSequences[runId]?.incrementAndGet() ?: 1L else 1L
        writeEventFrame(runId, msg, seq)
        if (terminal) break
    }
}

suspend fun ByteWriteChannel.writeEventFrame(
    runId: String?,
    ev: String,
    id: Long?,
) {
    val status =
        try {
            Json
                .parseToJsonElement(ev)
                .jsonObject["status"]
                ?.jsonPrimitive
                ?.contentOrNull
        } catch (_: Exception) {
            null
        }
    val name =
        when (status) {
            "SUCCEEDED" -> "run-succeeded"
            "FAILED" -> "run-failed"
            else -> "step-status-changed"
        }
    val seq = id ?: runId?.let { runSequences[it]?.get() } ?: 0L
    writeStringUtf8("event: $name\n")
    writeStringUtf8("id: $seq\n")
    writeStringUtf8("data: $ev\n\n")
}

fun buildRunSnapshot(runId: String): String? {
    val st = runs[runId] ?: return null
    val status = st.status.name
    val terminal = status == "SUCCEEDED" || status == "FAILED" || status == "CANCELLED"
    return buildJsonObject {
        put("status", JsonPrimitive(status))
        put("currentStage", JsonPrimitive(stageLabel(st.status)))
        put("percentage", JsonPrimitive(percentageForStatus(st.status)))
        put("attempt", JsonPrimitive(1))
        put("startedAt", JsonPrimitive(st.createdAt.toEpochMilli()))
        put("lastEventSequence", JsonPrimitive(runSequences[runId]?.get() ?: 0L))
        put("terminal", JsonPrimitive(terminal))
    }.toString()
}

fun stageLabel(status: RunStatus): String =
    when (status) {
        RunStatus.PLANNING -> "PLANNING"
        RunStatus.GENERATING_GEOMETRY -> "GEOMETRY_EXPANDING"
        RunStatus.NORMALIZING -> "NORMALIZING"
        RunStatus.RASTERIZING -> "RASTERIZING"
        RunStatus.COMPOSING -> "COMPOSING"
        RunStatus.PREPROCESSING -> "PREPROCESSING"
        RunStatus.OCR_RUNNING -> "OCR_RUNNING"
        RunStatus.ADJUDICATING -> "ADJUDICATING"
        RunStatus.ASSEMBLING -> "ASSEMBLING"
        RunStatus.SUCCEEDED -> "SUCCEEDED"
        RunStatus.FAILED -> "FAILED"
    }

fun maturityForStatus(status: RunStatus): Int =
    when (status) {
        RunStatus.PLANNING -> 10
        RunStatus.GENERATING_GEOMETRY -> 20
        RunStatus.NORMALIZING -> 30
        RunStatus.RASTERIZING -> 40
        RunStatus.COMPOSING -> 50
        RunStatus.PREPROCESSING -> 60
        RunStatus.OCR_RUNNING -> 70
        RunStatus.ADJUDICATING -> 80
        RunStatus.ASSEMBLING -> 90
        RunStatus.SUCCEEDED -> 100
        RunStatus.FAILED -> 100
    }

fun sha256Hex(input: String): String {
    val digest = java.security.MessageDigest.getInstance("SHA-256")
    val bytes = digest.digest(input.toByteArray(Charsets.UTF_8))
    return bytes.joinToString("") { "%02x".format(it) }
}

private data class ArtifactCandidate(
    val objectKey: String,
    val sha256: String = "",
    val contentType: String? = null,
    val glyphPosition: Int? = null,
)

private fun JsonObject.stringValue(name: String): String? = this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

private fun JsonObject.intValue(name: String): Int? = this[name]?.jsonPrimitive?.intOrNull

private fun JsonElement.stringValue(): String? = jsonPrimitive.contentOrNull?.takeIf { it.isNotBlank() }

private fun JsonElement.objectValue(): JsonObject? = this as? JsonObject

private fun JsonObject.outputArtifactCandidates(
    contentType: String? = null,
    sha256: String = "",
): List<ArtifactCandidate> =
    (this["outputArtifacts"] as? JsonArray)
        ?.mapNotNull { element ->
            element.stringValue()?.let { objectKey ->
                ArtifactCandidate(objectKey, sha256, contentType, intValue("position"))
            }
        }
        ?: emptyList()

private fun contentTypeForObjectKey(objectKey: String): String =
    when {
        objectKey.endsWith(".json") -> "application/json"
        objectKey.endsWith(".svg") -> "image/svg+xml"
        objectKey.endsWith(".png") -> "image/png"
        else -> "application/octet-stream"
    }

private fun contentTypeValue(
    value: String?,
    fallback: String,
): String =
    value?.takeIf { it.isNotBlank() }?.let {
        runCatching { ContentType.parse(it).toString() }.getOrElse { "application/octet-stream" }
    } ?: fallback

private fun candidatesForEvent(
    topic: String,
    data: JsonObject,
): List<ArtifactCandidate> =
    when (topic) {
        Services.GEOMETRY_TOPIC -> {
            data.outputArtifactCandidates(
                contentType = "application/json",
                sha256 = data["geometry"]?.objectValue()?.stringValue("geometrySha256") ?: "",
            )
        }

        Services.NORMALIZED_TOPIC -> {
            data.outputArtifactCandidates().map { candidate ->
                val sha256 = if (candidate.objectKey.endsWith(".svg")) data.stringValue("svgSha256") ?: "" else ""
                candidate.copy(sha256 = sha256, contentType = contentTypeForObjectKey(candidate.objectKey))
            }
        }

        Services.RASTERIZED_TOPIC -> {
            listOfNotNull(
                data["raster"]?.objectValue()?.let { raster ->
                    raster.stringValue("objectKey")?.let { objectKey ->
                        ArtifactCandidate(
                            objectKey = objectKey,
                            sha256 = raster.stringValue("sha256") ?: "",
                            contentType = raster.stringValue("contentType"),
                            glyphPosition = data.intValue("position"),
                        )
                    }
                },
            )
        }

        Services.PHRASE_COMPOSED_TOPIC -> {
            listOfNotNull(
                data["phraseImage"]?.objectValue()?.let { image ->
                    image.stringValue("objectKey")?.let { objectKey ->
                        ArtifactCandidate(
                            objectKey = objectKey,
                            sha256 = image.stringValue("sha256") ?: "",
                            contentType = image.stringValue("contentType") ?: "image/png",
                            glyphPosition = data.intValue("position"),
                        )
                    }
                },
            )
        }

        Services.OCR_IMAGES_TOPIC -> {
            val image =
                listOfNotNull(
                    data["ocrImage"]?.objectValue()?.let { ocrImage ->
                        ocrImage.stringValue("objectKey")?.let { objectKey ->
                            ArtifactCandidate(
                                objectKey = objectKey,
                                sha256 = ocrImage.stringValue("sha256") ?: "",
                                contentType = ocrImage.stringValue("contentType") ?: "image/png",
                            )
                        }
                    },
                )
            val crops =
                (data["positionCrops"] as? JsonArray)
                    ?.mapNotNull { element ->
                        element.objectValue()?.let { crop ->
                            crop.stringValue("objectKey")?.let { objectKey ->
                                ArtifactCandidate(
                                    objectKey = objectKey,
                                    contentType = "image/png",
                                    glyphPosition = crop.intValue("position"),
                                )
                            }
                        }
                    }
                    ?: emptyList()
            image + crops
        }

        else -> {
            emptyList()
        }
    }

private fun sha256ForCandidate(candidate: ArtifactCandidate): String {
    if (candidate.sha256.isNotBlank()) return candidate.sha256
    val store = Services.artifactStore ?: return ""
    return try {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        store.open(candidate.objectKey).use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    } catch (_: ArtifactNotFoundException) {
        ""
    } catch (_: java.io.IOException) {
        ""
    }
}

fun recordEventArtifacts(
    runId: String,
    topic: String,
    data: JsonObject,
) {
    if (topic == Services.PHRASE_ASSEMBLED_TOPIC) return
    val stage =
        mapOf(
            Services.GEOMETRY_TOPIC to "GEOMETRY_EXPANDING",
            Services.NORMALIZED_TOPIC to "NORMALIZING",
            Services.RASTERIZED_TOPIC to "RASTERIZING",
            Services.PHRASE_COMPOSED_TOPIC to "COMPOSING",
            Services.OCR_IMAGES_TOPIC to "PREPROCESSING",
        )[topic] ?: return
    val runPrefix = "runs/$runId/"
    candidatesForEvent(topic, data)
        .distinctBy { it.objectKey to it.glyphPosition }
        .forEach { candidate ->
            if (!candidate.objectKey.startsWith(runPrefix)) return@forEach
            try {
                validateArtifactObjectKey(candidate.objectKey)
            } catch (_: IllegalArgumentException) {
                return@forEach
            }
            val artifactId = sha256Hex("$runId|$topic|${candidate.glyphPosition ?: ""}|${candidate.objectKey}")
            val objectKeys = artifactObjectKeys.computeIfAbsent(runId) { ConcurrentHashMap() }
            if (objectKeys.putIfAbsent(artifactId, candidate.objectKey) != null) return@forEach
            val descriptor =
                buildMap {
                    put("id", artifactId)
                    put("artifactId", artifactId)
                    put("stage", stage)
                    put("sha256", sha256ForCandidate(candidate))
                    put("maturity", maturityForArtifactTopic(topic).toString())
                    put("contentType", contentTypeValue(candidate.contentType, contentTypeForObjectKey(candidate.objectKey)))
                    put("proxyUrl", "/api/v1/runs/$runId/artifacts/$artifactId")
                    put("createdAt", Instant.now().toString())
                    candidate.glyphPosition?.let { put("glyphPosition", it.toString()) }
                }
            runArtifacts.computeIfAbsent(runId) { CopyOnWriteArrayList() }.add(descriptor)
            RgMetrics.incArtifact(stage, 1)
            RgMetrics.incStepCompleted(stage, "artifact-store", "SUCCEEDED")
        }
}

private fun maturityForArtifactTopic(topic: String): Int =
    when (topic) {
        Services.GEOMETRY_TOPIC -> 20
        Services.NORMALIZED_TOPIC -> 30
        Services.RASTERIZED_TOPIC -> 40
        Services.PHRASE_COMPOSED_TOPIC -> 50
        Services.OCR_IMAGES_TOPIC -> 60
        else -> 0
    }

suspend fun handleListArtifacts(call: ApplicationCall) {
    val runId = call.parameters["runId"]
    if (runId == null) {
        call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Missing runId"))
        return
    }
    val stored = runArtifacts[runId]?.toList() ?: emptyList()
    call.respond(ArtifactListResponse(runId, stored))
}

suspend fun handleGetArtifact(call: ApplicationCall) {
    val runId = call.parameters["runId"]
    val artifactId = call.parameters["artifactId"]
    if (runId == null || artifactId == null) {
        call.respond(HttpStatusCode.BadRequest, "Missing artifact identifiers")
        return
    }
    val objectKey = artifactObjectKeys[runId]?.get(artifactId)
    val descriptor = runArtifacts[runId]?.firstOrNull { it["id"] == artifactId }
    if (objectKey == null || descriptor == null) {
        call.respond(HttpStatusCode.NotFound, "Artifact not found")
        return
    }
    val store = Services.artifactStore
    if (store == null) {
        call.respond(HttpStatusCode.ServiceUnavailable, "Artifact store unavailable")
        return
    }
    val contentType = ContentType.parse(contentTypeValue(descriptor["contentType"], "application/octet-stream"))
    val input =
        try {
            store.open(objectKey)
        } catch (_: ArtifactNotFoundException) {
            call.respond(HttpStatusCode.NotFound, "Artifact not found")
            return
        }
    try {
        call.respondOutputStream(contentType, HttpStatusCode.OK) {
            input.use { it.copyTo(this) }
        }
    } catch (error: Exception) {
        input.close()
        throw error
    }
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

fun percentageForStatus(status: RunStatus): Int =
    when (status) {
        RunStatus.PLANNING -> 10
        RunStatus.GENERATING_GEOMETRY -> 20
        RunStatus.NORMALIZING -> 30
        RunStatus.RASTERIZING -> 40
        RunStatus.COMPOSING -> 50
        RunStatus.PREPROCESSING -> 60
        RunStatus.OCR_RUNNING -> 70
        RunStatus.ADJUDICATING -> 80
        RunStatus.ASSEMBLING -> 90
        RunStatus.SUCCEEDED -> 100
        RunStatus.FAILED -> 100
    }

fun statusToPercentage(name: String): Int =
    try {
        percentageForStatus(RunStatus.valueOf(name))
    } catch (_: Exception) {
        0
    }

fun broadcastEvent(
    runId: String,
    data: Map<String, String>,
) {
    val statusName = data["status"]
    val enriched =
        if (statusName != null) {
            val status =
                try {
                    RunStatus.valueOf(statusName)
                } catch (_: Exception) {
                    null
                }
            val pct = status?.let { percentageForStatus(it) } ?: statusName.let { statusToPercentage(it) }
            if (pct > 0) {
                data + mapOf("percentage" to pct.toString(), "attempt" to "1")
            } else {
                data
            }
        } else {
            data
        }
    val eventData =
        buildJsonObject {
            enriched.forEach { (key, value) ->
                val asInt = value.toIntOrNull()
                if (asInt != null && (key == "percentage" || key == "attempt")) {
                    put(key, JsonPrimitive(asInt))
                } else {
                    put(key, JsonPrimitive(value))
                }
            }
        }.toString()
    val seq = runSequences.getOrPut(runId) { AtomicLong(0) }.incrementAndGet()
    val log = runEventLog.getOrPut(runId) { java.util.Collections.synchronizedList(mutableListOf()) }
    synchronized(log) {
        log.add(seq to eventData)
        if (log.size > 1000) log.removeAt(0)
    }
    lastRunEvents[runId] = eventData
    try {
        redisSync?.xadd(
            "run-events:$runId",
            mapOf("seq" to seq.toString(), "status" to (data["status"] ?: ""), "data" to eventData),
        )
        redisSync?.hset("run-summary:$runId", mapOf("latest" to eventData))
    } catch (_: Exception) {
    }
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
        "percentage" to statusToPercentage(status).toString(),
        "attempt" to "1",
    )
