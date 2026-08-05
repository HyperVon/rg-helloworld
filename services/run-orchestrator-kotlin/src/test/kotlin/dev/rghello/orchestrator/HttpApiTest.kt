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
import io.ktor.server.testing.testApplication
import io.ktor.utils.io.readUTF8Line
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.UUID

class HttpApiTest {
    @BeforeEach
    fun setUp() {
        runs.clear()
        idempotentRuns.clear()
        sseClients.clear()
        lastRunEvents.clear()
        Services.eventProducer = null
        Services.runStateStore = null
    }

    @AfterEach
    fun tearDown() {
        Services.eventProducer = null
        Services.runStateStore = null
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
            val client = createClient {}
            val runId = client.createRun("Hello World")

            val response = client.get("/api/v1/runs/$runId")
            assertEquals(HttpStatusCode.OK, response.status)
            val statusBody = response.bodyAsText()
            assertTrue(statusBody.contains("\"status\":\"PLANNING\""), "body: $statusBody")

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
    fun createRunWithProducerMovesToTempWorkerPending() =
        testApplication {
            application { module() }
            Services.eventProducer = FakeEventProducer()
            val client = createClient {}
            val runId = client.createRun("Hello World")

            assertEquals(RunStatus.TEMP_WORKER_PENDING, runs[runId]?.status)
            val store = FakeRunStateStore()
            Services.runStateStore = store
            val stored = client.get("/api/v1/runs/$runId")
            assertEquals(HttpStatusCode.OK, stored.status)
        }

    @Test
    fun sseStreamDeliversCompletionEvent() =
        runBlocking {
            val server = embeddedServer(Netty, port = 0, host = "127.0.0.1") { module() }
            server.start(wait = false)
            val base = "http://127.0.0.1:${server.engine.resolvedConnectors().first().port}"
            val client = HttpClient(CIO)
            try {
                val response =
                    client.post("$base/api/v1/runs") {
                        contentType(ContentType.Application.Json)
                        setBody("""{"message":"Hello World"}""")
                    }
                assertEquals(HttpStatusCode.Accepted, response.status)
                val parsed = Json.parseToJsonElement(response.bodyAsText()).jsonObject
                val runId = parsed.getValue("runId").jsonPrimitive.content
                val store = FakeRunStateStore()
                Services.runStateStore = store

                withTimeout(10_000) {
                    client.prepareRequest("$base/api/v1/runs/$runId/stream").execute { stream ->
                        val channel = stream.bodyAsChannel()
                        val first = channel.readUTF8Line()
                        assertEquals(": connected", first)
                        assertEquals("", channel.readUTF8Line())

                        val echo =
                            """
                            {
                              "specversion": "1.0",
                              "id": "${UUID.randomUUID()}",
                              "source": "temp-worker",
                              "type": "rg.temp-echo.v1",
                              "subject": "runs/$runId",
                              "datacontenttype": "application/json",
                              "correlationid": "$runId",
                              "data": {"assembledText": "Hello World"}
                            }
                            """.trimIndent()
                        launch { handleEchoResponse(runId, echo) }

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
            assertEquals(RunStatus.TEMP_WORKER_PENDING, runs[runId]?.status)
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
