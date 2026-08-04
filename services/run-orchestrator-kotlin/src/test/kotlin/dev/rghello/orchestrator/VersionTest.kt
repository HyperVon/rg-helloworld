package dev.rghello.orchestrator

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class VersionTest {
    @Test
    fun versionMatchesSkeleton() {
        assertEquals("0.0.0-skeleton", Version.VERSION)
    }

    @Test
    fun versionIsNotEmpty() {
        assertFalse(Version.VERSION.isBlank())
    }

    @Test
    fun serviceNameIsSet() {
        assertEquals("run-orchestrator", Version.SERVICE_NAME)
    }
}
