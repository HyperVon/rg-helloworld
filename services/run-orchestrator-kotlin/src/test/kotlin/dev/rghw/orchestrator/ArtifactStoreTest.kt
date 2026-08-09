package dev.rghw.orchestrator

import com.sun.net.httpserver.HttpServer
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.net.InetSocketAddress

class ArtifactStoreTest {
    @Test
    fun fromEnvironmentRequiresAllCredentials() {
        assertNull(MinioArtifactStore.fromEnvironment(emptyMap()))
        assertNull(MinioArtifactStore.fromEnvironment(mapOf("MINIO_ENDPOINT" to "http://localhost:9000")))
        assertNull(
            MinioArtifactStore.fromEnvironment(
                mapOf(
                    "MINIO_ENDPOINT" to "http://localhost:9000",
                    "MINIO_ACCESS_KEY" to "access",
                ),
            ),
        )
    }

    @Test
    fun fromEnvironmentBuildsConfiguredStore() {
        val store =
            MinioArtifactStore.fromEnvironment(
                mapOf(
                    "MINIO_ENDPOINT" to "http://localhost:9000",
                    "MINIO_ACCESS_KEY" to "access",
                    "MINIO_SECRET_KEY" to "secret",
                    "MINIO_BUCKET" to "artifacts",
                ),
            )

        assertNotNull(store)
    }

    @Test
    fun openMapsMinioNotFoundToArtifactNotFound() {
        val server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            val body =
                """
                <?xml version="1.0" encoding="UTF-8"?>
                <Error><Code>NoSuchKey</Code><Message>Not Found</Message></Error>
                """.trimIndent().toByteArray()
            exchange.responseHeaders.set("Content-Type", "application/xml")
            exchange.sendResponseHeaders(404, body.size.toLong())
            exchange.responseBody.use { it.write(body) }
        }
        server.start()

        try {
            val store =
                requireNotNull(
                    MinioArtifactStore.fromEnvironment(
                        mapOf(
                            "MINIO_ENDPOINT" to "http://127.0.0.1:${server.address.port}",
                            "MINIO_ACCESS_KEY" to "access",
                            "MINIO_SECRET_KEY" to "secret",
                        ),
                    ),
                )

            assertThrows(ArtifactNotFoundException::class.java) {
                store.open("runs/test/object")
            }
        } finally {
            server.stop(0)
        }
    }
}
