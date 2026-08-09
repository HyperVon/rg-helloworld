package dev.rghw.orchestrator

import io.minio.GetObjectArgs
import io.minio.MinioClient
import io.minio.errors.ErrorResponseException
import java.io.InputStream

interface ArtifactObjectStore {
    fun open(objectKey: String): InputStream
}

class ArtifactNotFoundException : RuntimeException()

fun validateArtifactObjectKey(objectKey: String) {
    require(objectKey.isNotBlank()) { "artifact object key must not be blank" }
    require(objectKey.startsWith("runs/")) { "artifact object key must be scoped to runs/" }
    require(!objectKey.startsWith("/")) { "artifact object key must be relative" }
    require('\\' !in objectKey) { "artifact object key must not contain backslashes" }
    require(objectKey.none(Char::isISOControl)) { "artifact object key must not contain control characters" }
    require(objectKey.split('/').none { it == "." || it == ".." }) {
        "artifact object key must not contain traversal segments"
    }
}

class MinioArtifactStore private constructor(
    private val client: MinioClient,
    private val bucket: String,
) : ArtifactObjectStore {
    override fun open(objectKey: String): InputStream {
        validateArtifactObjectKey(objectKey)
        return try {
            client.getObject(
                GetObjectArgs
                    .builder()
                    .bucket(bucket)
                    .`object`(objectKey)
                    .build(),
            )
        } catch (error: ErrorResponseException) {
            if (error.response().code == 404) {
                throw ArtifactNotFoundException()
            }
            throw error
        }
    }

    companion object {
        fun fromEnvironment(environment: Map<String, String> = System.getenv()): MinioArtifactStore? {
            val endpoint = environment["MINIO_ENDPOINT"] ?: return null
            val accessKey = environment["MINIO_ACCESS_KEY"] ?: return null
            val secretKey = environment["MINIO_SECRET_KEY"] ?: return null
            val bucket = environment["MINIO_BUCKET"] ?: "rube-goldberg-artifacts"

            return MinioArtifactStore(
                MinioClient
                    .builder()
                    .endpoint(endpoint)
                    .credentials(accessKey, secretKey)
                    .build(),
                bucket,
            )
        }
    }
}
