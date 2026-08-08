package dev.rghw.orchestrator

import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Severity
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TelemetryTest {
    @Test
    fun endpointPrefersEnvironmentOverrideThenCollectorDefault() {
        assertEquals(Telemetry.DEFAULT_ENDPOINT, Telemetry.endpoint { null })
        assertEquals(Telemetry.DEFAULT_ENDPOINT, Telemetry.endpoint { "  " })
        assertEquals("http://localhost:14317", Telemetry.endpoint { "http://localhost:14317" })
    }

    @Test
    fun telemetryStartsAndToleratesUnreachableCollector() {
        val unreachable = "http://127.0.0.1:14317"
        assertTrue(Telemetry.init(unreachable))
        assertTrue(Telemetry.init(unreachable))
        Telemetry.log(Severity.INFO, "unit test record", Attributes.empty())
        Telemetry.recordError("unit-test", IllegalStateException("handled"))
        Telemetry.shutdown()
        Telemetry.shutdown()
        Telemetry.log(Severity.INFO, "record after shutdown")
        assertFalse(Telemetry.init(unreachable))
    }
}
