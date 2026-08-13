package dev.rghw.orchestrator

import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.sdk.metrics.SdkMeterProvider
import org.junit.jupiter.api.Assertions.assertDoesNotThrow
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TelemetryTest {
    @Test
    fun endpointPrefersEnvironmentOverrideThenCollectorDefault() {
        assertEquals(Telemetry.DEFAULT_ENDPOINT, Telemetry.endpoint())
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

    @Test
    fun metricsBootstrapAndRecordersRemainSafeWithoutExporter() {
        val provider = SdkMeterProvider.builder().build()
        try {
            RgMetrics.init(provider.get("telemetry-test"))
            assertDoesNotThrow {
                RgMetrics.incRuns("SUCCEEDED")
                RgMetrics.incStepStarted("planning", "orchestrator")
                RgMetrics.incStepCompleted("planning", "orchestrator", "SUCCEEDED")
                RgMetrics.incRetry("planning", "transient")
                RgMetrics.incArtifact("glyph", 128)
                RgMetrics.incArtifact("default-bytes")
                RgMetrics.recordOcrConfidence(0.98, "full")
                RgMetrics.recordOcrConfidence(0.75)
                RgMetrics.setActiveRuns(2)
                RgMetrics.setSseConnections(1)
                RgMetrics.recordKafkaLag(3, "orchestrator", "run-events")
            }
        } finally {
            provider.shutdown()
        }
    }
}
