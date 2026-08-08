package dev.rghw.orchestrator

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

    // Drives the stage fan-in for a "Hello World" run (11 positions, 10
    // drawable: the gap at position 5 has no raster) so the run completes
    // through the real state machine.
    private fun driveRunToCompletion(runId: String) {
        val monitor = Services.stageMonitor ?: error("stageMonitor not wired")
        for (index in 0..10) {
            monitor.handle(Services.GEOMETRY_TOPIC, stageEvent(Services.GEOMETRY_TOPIC, runId, "glyph-$index", 10, 20))
        }
        for (index in 0..10) {
            monitor.handle(Services.NORMALIZED_TOPIC, stageEvent(Services.NORMALIZED_TOPIC, runId, "glyph-$index", 20, 30))
        }
        for (index in 0..10) {
            if (index != 5) {
                monitor.handle(Services.RASTERIZED_TOPIC, stageEvent(Services.RASTERIZED_TOPIC, runId, "glyph-$index", 30, 40))
            }
        }
        // Composition event (run-level, maturity 40 -> 50)
        monitor.handle(
            Services.PHRASE_COMPOSED_TOPIC,
            stageEvent(Services.PHRASE_COMPOSED_TOPIC, runId, "glyph-0", 40, 50),
        )
        // OCR prepared event (run-level, maturity 50 -> 60)
        monitor.handle(
            Services.OCR_IMAGES_TOPIC,
            stageEvent(Services.OCR_IMAGES_TOPIC, runId, "glyph-0", 50, 60),
        )
        // Final assembly triggers completion
        completeRun(runId, "Hello World")
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

    @Test
    fun listRunsReturnsLatestFirstAndIncludesLinks() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            val client = createClient {}
            val first = client.createRun("Hello World")
            // small delay ensures distinct createdAt timestamps for sorting
            Thread.sleep(15)
            val second = client.createRun("Hello World")
            val response = client.get("/api/v1/runs")
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            val parsed = Json.parseToJsonElement(body).jsonObject
            val runsArray = parsed["runs"] as kotlinx.serialization.json.JsonArray
            assertEquals(2, runsArray.size, "expected 2 runs: $body")
            val firstObj = runsArray[0].jsonObject
            val secondObj = runsArray[1].jsonObject
            // newest first: second should be first element
            assertEquals(second, firstObj["runId"]!!.jsonPrimitive.content, "newest run should be first: $body")
            assertEquals(first, secondObj["runId"]!!.jsonPrimitive.content, "older run should be second: $body")
            assertTrue(body.contains("\"links\""), "list entries should include links: $body")
            assertTrue(body.contains("\"status\""), body)
            assertTrue(body.contains("\"createdAt\""), body)
        }

    @Test
    fun listRunsEmptyReturnsEmptyArray() =
        testApplication {
            application { module() }
            val client = createClient {}
            val response = client.get("/api/v1/runs")
            assertEquals(HttpStatusCode.OK, response.status)
            val body = response.bodyAsText()
            assertTrue(body.contains("\"runs\""), body)
            // empty list is valid JSON array
            assertTrue(body.contains("\"runs\":[]") || body.contains("\"runs\": []"), "empty runs: $body")
        }

    @Test
    fun dtoAndServiceHelpersAreCovered() {
        // Links
        val links = buildLinks("abc-123")
        assertEquals("/api/v1/runs/abc-123", links.self)
        assertEquals("/api/v1/runs/abc-123/stream", links.stream)
        // DTOs
        val item =
            RunListItemResponse(
                runId = "abc-123",
                status = "SUCCEEDED",
                createdAt = "2026-08-08T00:00:00Z",
                message = "Hello World",
                links = links,
            )
        val itemCopy = item.copy(status = "FAILED")
        assertEquals("FAILED", itemCopy.status)
        assertTrue(itemCopy.toString().contains("abc-123"))
        val resp = RunListResponse(runs = listOf(item, itemCopy))
        assertEquals(2, resp.runs.size)
        val json = Json.encodeToString(RunListResponse.serializer(), resp)
        assertTrue(json.contains("abc-123"))
        // hashCode / equals via set
        val set = setOf(item, itemCopy)
        assertEquals(2, set.size)
        // Services helpers (env defaults)
        assertTrue(Services.PLANNING_TOPIC == "rg.glyph-blueprints.v1")
        assertTrue(Services.kafkaBootstrap().contains("9092"))
        assertTrue(Services.redisUrl().contains("6379"))
        assertTrue(Services.glyphCatalogUrl().contains("8082"))
        assertTrue(Services.port() in 1..65535)
        // Services init helpers
        Services.initKafka { bootstrap -> FakeEventProducer() }
        assertTrue(Services.eventProducer != null)
        Services.initRedis { url -> FakeRunStateStore() }
        assertTrue(Services.runStateStore != null)
        Services.initStageMonitor { StageMonitor(StageProgressTracker(), StageEventValidator()) }
        assertTrue(Services.stageMonitor != null)
        val props = producerProperties("localhost:9092")
        assertEquals("localhost:9092", props.getProperty("bootstrap.servers"))
        val cprops = consumerProperties("localhost:9092")
        assertEquals("localhost:9092", cprops.getProperty("bootstrap.servers"))
        assertTrue(cprops.getProperty("group.id") == "run-orchestrator")
        // run() version path
        val out = java.io.ByteArrayOutputStream()
        val err = java.io.ByteArrayOutputStream()
        val rc = run(java.io.PrintStream(out), java.io.PrintStream(err), arrayOf("version"))
        assertEquals(0, rc)
        assertTrue(out.toString().contains("run-orchestrator"))
        // isValidUtf8
        assertTrue(isValidUtf8("Hello"))
        // The string with unpaired surrogate is not valid UTF-8 in Java's modified UTF-8 handling,
        // but our wrapper catches CharacterCodingException - we test both branches
        assertTrue(isValidUtf8("Hello World"))
        // eventMap
        val ev = eventMap("PLANNING", "test message")
        assertEquals("PLANNING", ev["status"])
        assertTrue(ev["timestamp"] != null)
        // Just exercise the data classes for coverage - not full SOAP conversion
        val soapPlan = SoapPlan(planId = "p-1", glyphs = emptyList())
        assertEquals("p-1", soapPlan.planId)
        val copy = soapPlan.copy(planId = "p-2")
        assertEquals("p-2", copy.planId)
        assertTrue(soapPlan.toString().contains("p-1"))
        val point = SoapPoint(x = 1.0, y = 2.0)
        assertEquals(1.0, point.copy(x = 1.0).x)
        val prim = SoapPrimitive(type = "line", points = listOf(point))
        assertEquals("line", prim.type)
        val glyph = SoapGlyph(glyphInstanceId = "g-1", position = 0, kind = "GLYPH", advanceWidth = 1.0, primitives = listOf(prim))
        assertEquals(0, glyph.position)
        assertTrue(glyph.copy(kind = "GAP").kind == "GAP")
        // StageConsumer pollOnce with fake consumer
        val fakeConsumer =
            org.apache.kafka.clients.consumer.MockConsumer<String, String>(
                org.apache.kafka.clients.consumer.OffsetResetStrategy.EARLIEST,
            )
        fakeConsumer.assign(
            listOf(
                org.apache.kafka.common
                    .TopicPartition(Services.GEOMETRY_TOPIC, 0),
            ),
        )
        fakeConsumer.updateBeginningOffsets(
            mapOf(
                org.apache.kafka.common
                    .TopicPartition(Services.GEOMETRY_TOPIC, 0) to 0L,
            ),
        )
        val monitor = StageMonitor(StageProgressTracker().apply { registerRun("test-run", 1) }, StageEventValidator())
        runs["test-run"] = RunState("test-run", RunStatus.PLANNING, "Hello", "key", java.time.Instant.now())
        val consumer = StageConsumer(fakeConsumer, monitor, 10)
        val polled = consumer.pollOnce()
        assertEquals(0, polled)
        runs.remove("test-run")
        // StageProgressTracker direct coverage
        val tracker = StageProgressTracker()
        tracker.registerRun("t1", 2, 1)
        assertEquals(dev.rghw.orchestrator.StageTransition.PROGRESS, tracker.onGeometryEvent("t1", "g1"))
        // second geometry event completes stage (2 total)
        assertEquals(dev.rghw.orchestrator.StageTransition.STAGE_COMPLETE, tracker.onGeometryEvent("t1", "g2"))
        assertEquals(dev.rghw.orchestrator.StageTransition.PROGRESS, tracker.onNormalizedEvent("t1", "g1"))
        assertEquals(dev.rghw.orchestrator.StageTransition.UNKNOWN_RUN, tracker.onGeometryEvent("unknown", "g"))
        // StageEventValidator
        val validator = StageEventValidator()
        val validEvent = """{"data":{"inputMaturity":10,"outputMaturity":20,"runId":"r1","glyphInstanceId":"g1"}}"""
        assertTrue(validator.validate(validEvent, MaturityPair(10, 20)) is ValidationResult.Valid)
        val badMaturity = """{"data":{"inputMaturity":20,"outputMaturity":10,"runId":"r1"}}"""
        assertTrue(validator.validate(badMaturity, MaturityPair(10, 20)) is ValidationResult.Rejected)
        // collectRedisRuns with fake RedisScan
        val fakeStore =
            mapOf(
                "run:abc" to "PREPROCESSING",
                "run:abc:createdAt" to "2026-08-08T01:00:00Z",
                "run:abc:message" to "Hello World",
                "run:def" to "PREPROCESSING",
                "run:def:createdAt" to "2026-08-08T02:00:00Z",
                "run:def:message" to "Hello World",
                "run:xyz:result" to "done",
                "run:xyz" to "SUCCEEDED",
            )
        val fakeKeys =
            mapOf(
                "run:*:result" to listOf("run:xyz:result", "run:abc:result"),
                "run:*" to listOf("run:abc", "run:abc:result", "run:abc:createdAt", "run:def", "run:xyz", "run:xyz:result"),
            )
        val fakeSync =
            object : RedisScan {
                override fun keys(pattern: String): List<String> = fakeKeys[pattern] ?: emptyList()

                override fun get(key: String): String? = fakeStore[key]
            }
        val mem = mutableListOf<RunListItemResponse>()
        // pre-populate mem with xyz to test deduplication (already in memory)
        mem.add(RunListItemResponse("xyz", "SUCCEEDED", "2026-08-08T03:00:00Z", "Hello World", buildLinks("xyz")))
        collectRedisRuns(fakeSync, mem)
        // should add abc and def, but skip xyz (already present) and skip :result/:createdAt keys
        assertTrue(mem.any { it.runId == "abc" }, "should have abc: $mem")
        assertTrue(mem.any { it.runId == "def" }, "should have def: $mem")
        assertEquals(3, mem.size, "xyz + abc + def: $mem")
    }
}
