package dev.rghello.orchestrator

import io.ktor.utils.io.ByteChannel
import io.ktor.utils.io.readUTF8Line
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

class ApplicationTest {
    private lateinit var outBuf: ByteArrayOutputStream
    private lateinit var errBuf: ByteArrayOutputStream

    @BeforeEach
    fun setUp() {
        outBuf = ByteArrayOutputStream()
        errBuf = ByteArrayOutputStream()
        runs.clear()
        idempotentRuns.clear()
        expectedTexts.clear()
        sseClients.clear()
        lastRunEvents.clear()
        Services.eventProducer = null
        Services.runStateStore = null
        Services.planner = null
    }

    @AfterEach
    fun tearDown() {
        Services.eventProducer = null
        Services.runStateStore = null
        Services.planner = null
    }

    private fun streams(): Pair<ByteArrayOutputStream, ByteArrayOutputStream> = outBuf to errBuf

    @Test
    fun versionCommandPrintsVersionToStdout() {
        val (out, err) = streams()
        val code = run(PrintStream(out, true, StandardCharsets.UTF_8), PrintStream(err, true, StandardCharsets.UTF_8), arrayOf("version"))

        assertEquals(0, code)
        assertEquals("run-orchestrator 0.2.0-milestone4\n", out.toString(StandardCharsets.UTF_8))
        assertEquals("", err.toString(StandardCharsets.UTF_8))
    }

    @Test
    fun versionCommandRejectsExtraArgs() {
        val (out, err) = streams()
        val code =
            run(PrintStream(out, true, StandardCharsets.UTF_8), PrintStream(err, true, StandardCharsets.UTF_8), arrayOf("version", "extra"))

        assertEquals(0, code)
        assertEquals("run-orchestrator 0.2.0-milestone4\n", out.toString(StandardCharsets.UTF_8))
        assertEquals("", err.toString(StandardCharsets.UTF_8))
    }

    @Test
    fun runStateMachineTransitionsOnPlannedAndFailure() {
        assertEquals(
            RunStatus.SUCCEEDED,
            RunStateMachine.transition(RunStatus.PLANNING, RunEvent.PLANNED),
        )
        assertEquals(
            RunStatus.SUCCEEDED,
            RunStateMachine.transition(RunStatus.SUCCEEDED, RunEvent.PLANNED),
        )
        assertEquals(
            RunStatus.FAILED,
            RunStateMachine.transition(RunStatus.PLANNING, RunEvent.FAILURE_REPORTED),
        )
    }

    @Test
    fun eventMapIncludesStatusMessageAndTimestamp() {
        val event = eventMap("PLANNING", "Run created")

        assertEquals("PLANNING", event["status"])
        assertEquals("Run created", event["message"])
        assertTrue(event.containsKey("timestamp"))
    }

    @Test
    fun buildLinksExposesStreamEndpoint() {
        val links = buildLinks("run-123")

        assertEquals("/api/v1/runs/run-123", links.self)
        assertEquals("/api/v1/runs/run-123/events", links.events)
        assertEquals("/api/v1/runs/run-123/stream", links.stream)
        assertEquals("/api/v1/runs/run-123/artifacts", links.artifacts)
    }

    @Test
    fun completeRunUpdatesStateStoresAndPublishesFinalEvent() {
        val runId = UUID.randomUUID().toString()
        val runState =
            RunState(
                runId = runId,
                status = RunStatus.PLANNING,
                message = "Hello World",
                idempotencyKey = "key",
                createdAt = java.time.Instant.now(),
            )
        runs[runId] = runState

        val store = FakeRunStateStore()
        Services.runStateStore = store
        val producer = FakeEventProducer()
        Services.eventProducer = producer

        val sseChannel = Channel<String>(1)
        sseClients[runId] = CopyOnWriteArrayList(listOf(SseClient(sseChannel)))

        completeRun(runId, "Hello World")

        assertEquals("Hello World", store.result)
        assertEquals("SUCCEEDED", store.status)
        assertEquals(RunStatus.SUCCEEDED, runs[runId]?.status)
        val sent = producer.sent.single()
        assertEquals(Services.RUN_EVENTS_TOPIC, sent.first)
        assertEquals(runId, sent.second)
        assertTrue(sent.third.contains("assembledText"))
        assertTrue(sent.third.contains("Hello World"))

        val broadcast = sseChannel.tryReceive().getOrNull()
        assertTrue(broadcast != null && broadcast.contains("SUCCEEDED"))
    }

    @Test
    fun completeRunIgnoresUnknownRun() {
        completeRun(UUID.randomUUID().toString(), "ignored")
        assertTrue(runs.isEmpty())
    }

    @Test
    fun failRunMarksFailedAndBroadcasts() {
        val runId = UUID.randomUUID().toString()
        runs[runId] =
            RunState(
                runId = runId,
                status = RunStatus.PLANNING,
                message = "Hello World",
                idempotencyKey = "key",
                createdAt = java.time.Instant.now(),
            )
        val store = FakeRunStateStore()
        Services.runStateStore = store
        val sseChannel = Channel<String>(1)
        sseClients[runId] = CopyOnWriteArrayList(listOf(SseClient(sseChannel)))

        failRun(runId, "SOAP planning failed: boom")

        assertEquals(RunStatus.FAILED, runs[runId]?.status)
        assertEquals("FAILED", store.status)
        val broadcast = sseChannel.tryReceive().getOrNull()
        assertTrue(broadcast != null && broadcast.contains("FAILED"), "broadcast: $broadcast")
    }

    @Test
    fun blueprintEventDataContainsOnlyAllowedFields() {
        val glyph =
            SoapGlyph(
                glyphInstanceId = "g-1",
                position = 0,
                kind = "DRAWABLE",
                advanceWidth = 1.0,
                primitives = listOf(SoapPrimitive("POLYLINE", listOf(SoapPoint(0.1, 0.0), SoapPoint(0.9, 1.0)))),
            )

        val data = blueprintEventData("run-1", "plan-1", "step-1", glyph)

        assertEquals("run-1", data.getValue("runId").toString().trim('"'))
        assertEquals("plan-1", data.getValue("planId").toString().trim('"'))
        assertEquals("1", data.getValue("attempt").toString())
        assertEquals(
            "plan-glyphs",
            data
                .getValue("transformation")
                .toString()
                .substringAfter("\"name\":\"")
                .substringBefore('"'),
        )
        assertTrue(data.getValue("glyphs").toString().contains("\"glyphInstanceId\":\"g-1\""))
        assertTrue(data.getValue("glyphs").toString().contains("\"position\":0"))
        val prohibited = listOf("message", "targetText", "expectedCharacter", "unicodeCodePoint", "characterName", "glyphLabel")
        val serialized = data.values.joinToString(",")
        for (field in prohibited) {
            assertFalse(serialized.contains(field), "blueprint data must not contain $field")
        }
    }

    @Test
    fun blueprintEventDataCarriesGapKindAndWidth() {
        val gap =
            SoapGlyph(
                glyphInstanceId = "g-gap",
                position = 5,
                kind = "GAP",
                advanceWidth = 0.6,
                primitives = emptyList(),
            )

        val data = blueprintEventData("run-1", "plan-1", "step-1", gap)

        assertTrue(data.getValue("glyphs").toString().contains("\"kind\":\"GAP\""))
        assertTrue(data.getValue("glyphs").toString().contains("\"advanceWidth\":0.6"))
        assertTrue(data.getValue("glyphs").toString().contains("\"primitives\":[]"))
    }

    @Test
    fun servicesWiringAcceptsFakes() {
        Services.initKafka { FakeEventProducer() }
        Services.initRedis { FakeRunStateStore() }

        assertTrue(Services.eventProducer is FakeEventProducer)
        assertTrue(Services.runStateStore is FakeRunStateStore)
    }

    @Test
    fun producerPropertiesContainBootstrapAndSerializers() {
        val props = producerProperties("localhost:9092")

        assertEquals("localhost:9092", props.getProperty("bootstrap.servers"))
        assertEquals("all", props.getProperty("acks"))
        assertTrue(props.getProperty("key.serializer").contains("StringSerializer"))
        assertTrue(props.getProperty("value.serializer").contains("StringSerializer"))
    }

    @Test
    fun kafkaEventProducerDelegatesToSendFunction() {
        var capturedTopic: String? = null
        var capturedKey: String? = null
        var capturedValue: String? = null
        val sender =
            KafkaEventProducer { topic, key, value ->
                capturedTopic = topic
                capturedKey = key
                capturedValue = value
            }

        sender.send("test-topic", "key-1", "value-1")

        assertEquals("test-topic", capturedTopic)
        assertEquals("key-1", capturedKey)
        assertEquals("value-1", capturedValue)
    }

    @Test
    fun redisRunStateStoreDelegatesToSyncCommands() {
        var lastSetStatusKey: String? = null
        var lastSetResultKey: String? = null
        var statusGetKey: String? = null

        val sync =
            java.lang.reflect.Proxy.newProxyInstance(
                io.lettuce.core.api.sync.RedisCommands::class.java.classLoader,
                arrayOf(io.lettuce.core.api.sync.RedisCommands::class.java),
            ) { _, method, args ->
                when (method.name) {
                    "setex" -> {
                        val key = args[0] as String
                        if (key.endsWith(":result")) lastSetResultKey = key else lastSetStatusKey = key
                        "OK"
                    }

                    "get" -> {
                        statusGetKey = args[0] as String
                        "SUCCEEDED"
                    }

                    else -> {
                        null
                    }
                }
            } as io.lettuce.core.api.sync.RedisCommands<String, String>

        val store = RedisRunStateStore(sync)
        store.setRunStatus("r1", RunStatus.PLANNING)
        store.setRunResult("r1", "Hello World")

        assertEquals("run:r1", lastSetStatusKey)
        assertEquals("run:r1:result", lastSetResultKey)
        store.getRunStatus("r1")
        assertEquals("run:r1", statusGetKey)
        assertEquals("SUCCEEDED", store.getRunStatus("r1"))
    }

    @Test
    fun broadcastEventRecordsLastEventForReplay() {
        lastRunEvents.clear()
        broadcastEvent("run-1", mapOf("status" to "SUCCEEDED", "assembledText" to "Hello World"))

        val replay = lastRunEvents["run-1"]
        assertTrue(replay != null && replay.contains("SUCCEEDED"), "replay: $replay")
        assertTrue(replay != null && replay.contains("Hello World"), "replay: $replay")
    }

    @Test
    fun writeSseLoopEmitsHeartbeatThenReplayThenEvents() =
        runBlocking {
            val out = ByteChannel()
            val events = Channel<String>(Channel.BUFFERED)
            val job =
                launch {
                    try {
                        out.writeSseLoop(events, replayEvent = """{"status":"SUCCEEDED","assembledText":"Hello World"}""")
                    } catch (_: CancellationException) {
                    } finally {
                        out.close()
                    }
                }
            events.send("""{"status":"SUCCEEDED","assembledText":"Hello World"}""")
            yield()
            events.cancel()
            job.join()

            val text =
                buildString {
                    while (true) {
                        val line = out.readUTF8Line() ?: break
                        append(line).append('\n')
                    }
                }
            assertTrue(text.contains(": connected"), "text: $text")
            assertEquals(2, Regex("data: ").findAll(text).count(), "text: $text")
        }

    @Test
    fun isValidUtf8AcceptsWellFormedText() {
        assertTrue(isValidUtf8("Hello World"))
        assertTrue(isValidUtf8(""))
        assertFalse(isValidUtf8("\uD800"))
    }
}

class FakeEventProducer : EventProducer {
    val sent = mutableListOf<Triple<String, String, String>>()

    override fun send(
        topic: String,
        key: String,
        value: String,
    ) {
        sent.add(Triple(topic, key, value))
    }

    val lastValue: String? get() = sent.lastOrNull()?.third
}

class FakeRunStateStore : RunStateStore {
    var status: String? = null
    var result: String? = null

    override fun setRunStatus(
        runId: String,
        status: RunStatus,
    ) {
        this.status = status.name
    }

    override fun setRunResult(
        runId: String,
        result: String,
    ) {
        this.result = result
    }

    override fun getRunStatus(runId: String): String? = status
}

class FakeGlyphPlanner : GlyphPlanner {
    override fun plan(
        message: String,
        alphabet: String,
        variant: String,
    ): SoapPlan {
        val glyphs =
            message.mapIndexed { index, char ->
                if (char == ' ') {
                    SoapGlyph("gap-$index", index, "GAP", 0.6, emptyList())
                } else {
                    SoapGlyph(
                        glyphInstanceId = "glyph-$index",
                        position = index,
                        kind = "DRAWABLE",
                        advanceWidth = 1.0,
                        primitives =
                            listOf(
                                SoapPrimitive(
                                    "POLYLINE",
                                    listOf(SoapPoint(0.1, 0.0), SoapPoint(0.9, 1.0)),
                                ),
                            ),
                    )
                }
            }
        return SoapPlan(planId = "plan-$message", glyphs = glyphs)
    }
}
