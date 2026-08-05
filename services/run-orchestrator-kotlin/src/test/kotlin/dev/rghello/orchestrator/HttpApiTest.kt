package dev.rghello.orchestrator

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.prepareRequest
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsChannel
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.routing
import io.ktor.server.testing.testApplication
import io.ktor.utils.io.readUTF8Line
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.UUID

class HttpApiTest {
    @BeforeEach
    fun setUp() {
        runs.clear()
        idempotentRuns.clear()
        expectedTexts.clear()
        sseClients.clear()
        lastRunEvents.clear()
        Services.eventProducer = null
        Services.runStateStore = null
        Services.planner = FakeGlyphPlanner()
        Services.stageMonitor = StageMonitor(StageProgressTracker(), StageEventValidator())
    }

    @AfterEach
    fun tearDown() {
        Services.eventProducer = null
        Services.runStateStore = null
        Services.planner = null
        Services.stageMonitor = null
    }

    // Drives the stage fan-in for a "Hello World" run (11 positions) so the
    // run completes through the real state machine.
    private fun driveRunToCompletion(runId: String) {
        val monitor = Services.stageMonitor ?: error("stageMonitor not wired")
        for (index in 0..10) {
            monitor.handle(Services.GEOMETRY_TOPIC, stageEvent(Services.GEOMETRY_TOPIC, runId, "glyph-$index", 10, 20))
        }
        for (index in 0..10) {
            monitor.handle(Services.NORMALIZED_TOPIC, stageEvent(Services.NORMALIZED_TOPIC, runId, "glyph-$index", 20, 30))
        }
    }

    private suspend fun io.ktor.client.HttpClient.createRun(
        message: String,
        idempotencyKey: String? = null,
    ): String {
        val response =
            post("/api/v1/runs") {
                contentType(ContentType.Application.Json)
                setBody("""{"message":"$message"}""")
                if (idempotencyKey != null) {
                    header("Idempotency-Key", idempotencyKey)
                }
            }
        assertEquals(HttpStatusCode.Accepted, response.status)
        val body = response.bodyAsText()
        val parsed = Json.parseToJsonElement(body).jsonObject
        assertTrue(parsed.getValue("runId").jsonPrimitive.contentOrNull != null)
        return parsed.getValue("runId").jsonPrimitive.content
    }

    @Test
    fun healthzReturnsOk() =
        testApplication {
            application { module() }
            val client = createClient {}
            val response = client.get("/healthz")
            assertEquals(HttpStatusCode.OK, response.status)
            assertEquals("OK", response.bodyAsText())
        }

    @Test
    fun createRunReturnsAcceptedWithLinks() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            val client = createClient {}
            val runId = client.createRun("Hello World")

            val response = client.get("/api/v1/runs/$runId")
            assertEquals(HttpStatusCode.OK, response.status)
            val statusBody = response.bodyAsText()
            assertTrue(statusBody.contains("\"status\":\"GENERATING_GEOMETRY\""), "body: $statusBody")

            driveRunToCompletion(runId)

            val completed = client.get("/api/v1/runs/$runId")
            assertTrue(completed.bodyAsText().contains("\"status\":\"SUCCEEDED\""), "body: ${completed.bodyAsText()}")

            val links = client.post("/api/v1/runs/$runId/cancel")
            assertEquals(HttpStatusCode.OK, links.status)
            assertTrue(links.bodyAsText().contains("CANCEL_REQUESTED"))

            val artifacts = client.get("/api/v1/runs/$runId/artifacts")
            assertEquals(HttpStatusCode.OK, artifacts.status)
            assertTrue(artifacts.bodyAsText().contains("\"artifacts\":[]"))
        }

    @Test
    fun createRunWithSameIdempotencyKeyConflicts() =
        testApplication {
            application { module() }
            val client = createClient {}
            val key = UUID.randomUUID().toString()
            client.createRun("Hello World", key)

            val second =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody("""{"message":"Hello World"}""")
                    header("Idempotency-Key", key)
                }
            assertEquals(HttpStatusCode.Conflict, second.status)
        }

    @Test
    fun createRunEmitsOneBlueprintEventPerPosition() =
        testApplication {
            application { module() }
            val producer = FakeEventProducer()
            Services.eventProducer = producer
            Services.planner = FakeGlyphPlanner()
            val client = createClient {}
            val runId = client.createRun("Hello World")

            assertEquals(RunStatus.GENERATING_GEOMETRY, runs[runId]?.status)
            assertEquals("Hello World", expectedTexts[runId])
            val blueprints = producer.sent.filter { it.first == Services.PLANNING_TOPIC }
            assertEquals(11, blueprints.size, "expected 11 blueprint events")
            blueprints.forEachIndexed { index, sent ->
                assertEquals(runId, sent.second.substringBefore(':'), "partition key for $index")
                assertTrue(sent.second.contains(':'), "partition key must include glyphInstanceId")
                assertTrue(sent.third.contains("\"position\":$index"), "event $index: ${sent.third}")
            }
            assertEquals(0, blueprints.filter { it.third.contains("\"message\"") }.size)
            assertEquals(
                0,
                producer.sent.filter { it.first == Services.RUN_EVENTS_TOPIC }.size,
                "no final event before the normalized fan-in",
            )

            driveRunToCompletion(runId)

            assertTrue(producer.sent.any { it.first == Services.RUN_EVENTS_TOPIC })
            assertEquals(RunStatus.SUCCEEDED, runs[runId]?.status)
        }

    @Test
    fun createRunBlueprintEventsExcludePlaintextAndCodePoints() =
        testApplication {
            application { module() }
            val producer = FakeEventProducer()
            Services.eventProducer = producer
            Services.planner = FakeGlyphPlanner()
            val client = createClient {}
            client.createRun("Hello World")

            val prohibited = listOf("message", "targetText", "expectedCharacter", "unicodeCodePoint", "characterName", "glyphLabel")
            val blueprints = producer.sent.filter { it.first == Services.PLANNING_TOPIC }
            for (sent in blueprints) {
                for (field in prohibited) {
                    assertFalse(sent.third.contains(field), "blueprint event must not contain $field: ${sent.third}")
                }
            }
        }

    @Test
    fun createRunBlueprintEventsCarryGapAtPositionFive() =
        testApplication {
            application { module() }
            val producer = FakeEventProducer()
            Services.eventProducer = producer
            Services.planner = FakeGlyphPlanner()
            val client = createClient {}
            client.createRun("Hello World")

            val gapEvent =
                producer.sent
                    .filter { it.first == Services.PLANNING_TOPIC }
                    .first { it.third.contains("\"position\":5") }
            assertTrue(gapEvent.third.contains("\"kind\":\"GAP\""), gapEvent.third)
            assertTrue(gapEvent.third.contains("\"advanceWidth\":0.6"), gapEvent.third)
        }

    @Test
    fun createRunWithoutPlannerFailsRun() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            Services.planner = null
            val client = createClient {}

            val response =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody("""{"message":"Hello World"}""")
                }
            assertEquals(HttpStatusCode.InternalServerError, response.status)
        }

    @Test
    fun createRunWithUnsupportedMessageFailsRun() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            Services.planner =
                object : GlyphPlanner {
                    override fun plan(
                        message: String,
                        alphabet: String,
                        variant: String,
                    ): SoapPlan = throw RuntimeException("Unsupported character U+0021")
                }
            val client = createClient {}

            val response =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody("""{"message":"Hello World!"}""")
                }
            assertEquals(HttpStatusCode.InternalServerError, response.status)
            val body = response.bodyAsText()
            assertTrue(body.contains("FAILED"), body)
        }

    @Test
    fun createRunRejectsInvalidUtf8() =
        testApplication {
            application { module() }
            val client = createClient {}

            val response =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody("""{"message":"\ud800"}""")
                }
            assertEquals(HttpStatusCode.BadRequest, response.status)
        }

    @Test
    fun sseStreamReplaysCompletedRunEvent() =
        runBlocking {
            val server = embeddedServer(Netty, port = 0, host = "127.0.0.1") { module() }
            server.start(wait = false)
            val base = "http://127.0.0.1:${server.engine.resolvedConnectors().first().port}"
            val client = HttpClient(CIO)
            try {
                val store = FakeRunStateStore()
                Services.runStateStore = store
                Services.eventProducer = FakeEventProducer()
                val response =
                    client.post("$base/api/v1/runs") {
                        contentType(ContentType.Application.Json)
                        setBody("""{"message":"Hello World"}""")
                    }
                assertEquals(HttpStatusCode.Accepted, response.status)
                val parsed = Json.parseToJsonElement(response.bodyAsText()).jsonObject
                val runId = parsed.getValue("runId").jsonPrimitive.content

                driveRunToCompletion(runId)

                withTimeout(10_000) {
                    client.prepareRequest("$base/api/v1/runs/$runId/stream").execute { stream ->
                        val channel = stream.bodyAsChannel()
                        val first = channel.readUTF8Line()
                        assertEquals(": connected", first)
                        assertEquals("", channel.readUTF8Line())

                        var eventLine: String? = null
                        while (eventLine == null || !eventLine.contains("SUCCEEDED")) {
                            eventLine = channel.readUTF8Line()
                            if (eventLine == null) break
                        }
                        channel.cancel(java.util.concurrent.CancellationException("test"))

                        assertTrue(
                            eventLine != null && eventLine.startsWith("data: ") && eventLine.contains("SUCCEEDED"),
                            "event: $eventLine",
                        )
                        assertTrue(
                            eventLine != null && eventLine.contains("Hello World"),
                            "event: $eventLine",
                        )
                        assertEquals("Hello World", store.result)
                    }
                }
            } finally {
                client.close()
                server.stop(gracePeriodMillis = 100, timeoutMillis = 1_000)
            }
        }

    @Test
    fun createRunWithOptionsParsesOptions() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            Services.planner = FakeGlyphPlanner()
            val client = createClient {}

            val response =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody(
                        """{"message":"Hello World","options":{"retainArtifacts":true,"maximumQualityAttempts":5,"renderProfile":"FAST"}}""",
                    )
                }
            assertEquals(HttpStatusCode.Accepted, response.status)
            val parsed = Json.parseToJsonElement(response.bodyAsText()).jsonObject
            val runId = parsed.getValue("runId").jsonPrimitive.content
            assertEquals(RunStatus.GENERATING_GEOMETRY, runs[runId]?.status)
        }

    @Test
    fun malformedCreateRunBodyReturnsInternalServerError() =
        testApplication {
            application { module() }
            val client = createClient {}

            val response =
                client.post("/api/v1/runs") {
                    contentType(ContentType.Application.Json)
                    setBody("{invalid json")
                }
            assertEquals(HttpStatusCode.InternalServerError, response.status)
        }

    @Test
    fun handlersWithoutRunIdReturnBadRequest() =
        testApplication {
            application {
                module()
                routing {
                    get("/noid/get") { handleGetRun(call) }
                    get("/noid/stream") { handleSseStream(call) }
                    post("/noid/cancel") { handleCancelRun(call) }
                }
            }
            val client = createClient {}
            assertEquals(HttpStatusCode.BadRequest, client.get("/noid/get").status)
            assertEquals(HttpStatusCode.BadRequest, client.get("/noid/stream").status)
            assertEquals(HttpStatusCode.BadRequest, client.post("/noid/cancel").status)
        }

    @Test
    fun buildServerStartsAndServesHealthz() =
        runBlocking {
            val server = buildServer(0)
            server.start(wait = false)
            val client = HttpClient(CIO)
            try {
                val port =
                    server.engine
                        .resolvedConnectors()
                        .first()
                        .port
                val response = client.get("http://127.0.0.1:$port/healthz")
                assertEquals(HttpStatusCode.OK, response.status)
                assertEquals("OK", response.bodyAsText())
            } finally {
                client.close()
                server.stop(gracePeriodMillis = 100, timeoutMillis = 1_000)
            }
        }
}
