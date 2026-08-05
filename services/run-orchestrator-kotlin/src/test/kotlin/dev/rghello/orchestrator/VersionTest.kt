package dev.rghello.orchestrator

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Test

class VersionTest {
    @Test
    fun versionMatchesMilestoneThree() {
        assertEquals("0.1.0-milestone3", Version.VERSION)
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
