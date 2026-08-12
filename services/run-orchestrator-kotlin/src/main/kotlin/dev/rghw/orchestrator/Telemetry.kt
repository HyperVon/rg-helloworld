package dev.rghw.orchestrator

import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Logger
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.metrics.Meter
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator
import io.opentelemetry.context.propagation.ContextPropagators
import io.opentelemetry.exporter.otlp.logs.OtlpGrpcLogRecordExporter
import io.opentelemetry.exporter.otlp.metrics.OtlpGrpcMetricExporter
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.logs.SdkLoggerProvider
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor
import io.opentelemetry.sdk.metrics.SdkMeterProvider
import io.opentelemetry.sdk.metrics.export.PeriodicMetricReader
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor
import java.time.Duration
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * OTLP/gRPC telemetry bootstrap: traces and log records are exported to the
 * collector and the SDK is registered as the global OpenTelemetry instance.
 *
 * Integrity rule: emitted records carry stage, status, and error-type metadata
 * only. The requested plaintext, expected characters, glyph content, and image
 * bytes must never be passed to [log] or [recordError].
 */
object Telemetry {
    const val DEFAULT_ENDPOINT: String = "http://otel-collector.rube-goldberg:4317"

    private const val SCOPE_NAME: String = "dev.rghw.orchestrator"
    private const val SHUTDOWN_TIMEOUT_SECONDS: Long = 2

    private val exportTimeout: Duration = Duration.ofSeconds(5)
    private val serviceNameKey = AttributeKey.stringKey("service.name")
    private val serviceVersionKey = AttributeKey.stringKey("service.version")
    private val endpointKey = AttributeKey.stringKey("otel.endpoint")
    private val stageKey = AttributeKey.stringKey("stage")
    private val errorTypeKey = AttributeKey.stringKey("error.type")

    @Volatile
    private var sdk: OpenTelemetrySdk? = null

    @Volatile
    private var logger: Logger? = null

    @Volatile
    private var meter: Meter? = null

    fun endpoint(lookup: (String) -> String? = System::getenv): String =
        lookup("OTEL_EXPORTER_OTLP_ENDPOINT")?.takeIf { it.isNotBlank() } ?: DEFAULT_ENDPOINT

    /**
     * Builds and globally registers the tracer, logger, and meter providers. Returns
     * false when telemetry could not be started; the service keeps running
     * either way, since an unreachable collector must never fail a run.
     */
    fun init(endpoint: String = endpoint()): Boolean {
        if (sdk != null) return true
        return try {
            val resource = telemetryResource()
            val started =
                OpenTelemetrySdk
                    .builder()
                    .setTracerProvider(tracerProvider(resource, endpoint))
                    .setLoggerProvider(loggerProvider(resource, endpoint))
                    .setMeterProvider(meterProvider(resource, endpoint))
                    .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                    .buildAndRegisterGlobal()
            sdk = started
            logger = started.logsBridge.get(SCOPE_NAME)
            meter = started.getMeter(SCOPE_NAME)
            RgMetrics.init(meter!!)
            Runtime.getRuntime().addShutdownHook(Thread(::shutdown, "otel-shutdown"))
            started
                .getTracer(SCOPE_NAME)
                .spanBuilder("orchestrator.startup")
                .startSpan()
                .end()
            log(Severity.INFO, "orchestrator telemetry started", Attributes.of(endpointKey, endpoint))
            true
        } catch (e: Exception) {
            System.err.println("[otel] telemetry disabled: ${e.javaClass.simpleName}: ${e.message}")
            false
        }
    }

    fun log(
        severity: Severity,
        message: String,
        attributes: Attributes = Attributes.empty(),
    ) {
        val target = logger ?: return
        try {
            target
                .logRecordBuilder()
                .setSeverity(severity)
                .setSeverityText(severity.name)
                .setBody(message)
                .setAllAttributes(attributes)
                .emit()
        } catch (e: Exception) {
            System.err.println("[otel] log record dropped: ${e.javaClass.simpleName}")
        }
    }

    /** Records a handled failure. The throwable message is deliberately omitted: it can echo request content. */
    fun recordError(
        stage: String,
        error: Throwable,
    ) {
        log(
            Severity.ERROR,
            "stage failed",
            Attributes.of(stageKey, stage, errorTypeKey, error.javaClass.simpleName),
        )
    }

    fun shutdown() {
        val active = sdk ?: return
        sdk = null
        logger = null
        meter = null
        active.shutdown().join(SHUTDOWN_TIMEOUT_SECONDS, TimeUnit.SECONDS)
    }

    private fun telemetryResource(): Resource =
        Resource.getDefault().merge(
            Resource.create(Attributes.of(serviceNameKey, Version.SERVICE_NAME, serviceVersionKey, Version.VERSION)),
        )

    private fun tracerProvider(
        resource: Resource,
        endpoint: String,
    ): SdkTracerProvider {
        val exporter =
            OtlpGrpcSpanExporter
                .builder()
                .setEndpoint(endpoint)
                .setTimeout(exportTimeout)
                .build()
        return SdkTracerProvider
            .builder()
            .setResource(resource)
            .addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
            .build()
    }

    private fun loggerProvider(
        resource: Resource,
        endpoint: String,
    ): SdkLoggerProvider {
        val exporter =
            OtlpGrpcLogRecordExporter
                .builder()
                .setEndpoint(endpoint)
                .setTimeout(exportTimeout)
                .build()
        return SdkLoggerProvider
            .builder()
            .setResource(resource)
            .addLogRecordProcessor(BatchLogRecordProcessor.builder(exporter).build())
            .build()
    }

    private fun meterProvider(
        resource: Resource,
        endpoint: String,
    ): SdkMeterProvider {
        val exporter =
            OtlpGrpcMetricExporter
                .builder()
                .setEndpoint(endpoint)
                .setTimeout(exportTimeout)
                .build()
        return SdkMeterProvider
            .builder()
            .setResource(resource)
            .registerMetricReader(PeriodicMetricReader.builder(exporter).setInterval(Duration.ofSeconds(10)).build())
            .build()
    }
}

object RgMetrics {
    private var runsTotal: io.opentelemetry.api.metrics.LongCounter? = null
    private var stepStarted: io.opentelemetry.api.metrics.LongCounter? = null
    private var stepCompleted: io.opentelemetry.api.metrics.LongCounter? = null
    private var stepRetries: io.opentelemetry.api.metrics.LongCounter? = null
    private var artifactsCreated: io.opentelemetry.api.metrics.LongCounter? = null
    private var artifactBytes: io.opentelemetry.api.metrics.LongCounter? = null
    private var ocrConfidence: io.opentelemetry.api.metrics.DoubleHistogram? = null
    private var kafkaLag: io.opentelemetry.api.metrics.DoubleHistogram? = null
    private var activeRunsGauge: AtomicLong = AtomicLong(0)
    private var sseConnectionsGauge: AtomicLong = AtomicLong(0)

    fun init(meter: Meter) {
        runsTotal = meter.counterBuilder("rg_runs_total").setDescription("Total runs by status").build()
        stepStarted = meter.counterBuilder("rg_step_started_total").setDescription("Steps started").build()
        stepCompleted = meter.counterBuilder("rg_step_completed_total").setDescription("Steps completed").build()
        stepRetries = meter.counterBuilder("rg_step_retries_total").setDescription("Step retries").build()
        artifactsCreated = meter.counterBuilder("rg_artifacts_created_total").setDescription("Artifacts created").build()
        artifactBytes = meter.counterBuilder("rg_artifact_bytes").setDescription("Artifact bytes").build()
        ocrConfidence = meter.histogramBuilder("rg_ocr_confidence").setDescription("OCR confidence").build()
        kafkaLag = meter.histogramBuilder("rg_kafka_consumer_lag").setDescription("Kafka consumer lag").build()
        meter.gaugeBuilder("rg_active_runs").setDescription("Active runs").buildWithCallback { it.record(activeRunsGauge.get().toDouble()) }
        meter.gaugeBuilder("rg_ui_sse_connections").setDescription("SSE connections").buildWithCallback {
            it.record(sseConnectionsGauge.get().toDouble())
        }
        meter.gaugeBuilder("rg_run_end_to_end_seconds").setDescription("End-to-end run duration").buildWithCallback { }
        meter.histogramBuilder("rg_step_duration_seconds").setDescription("Step duration").build()
        meter.histogramBuilder("rg_glyph_segment_count").setDescription("Glyph segment count").build()
    }

    fun incRuns(status: String) {
        try {
            runsTotal?.add(1, Attributes.of(AttributeKey.stringKey("status"), status))
        } catch (_: Exception) {
        }
    }

    fun incStepStarted(
        step: String,
        service: String,
    ) {
        try {
            stepStarted?.add(
                1,
                Attributes.of(
                    AttributeKey.stringKey("step"),
                    step,
                    AttributeKey.stringKey("service"),
                    service,
                ),
            )
        } catch (_: Exception) {
        }
    }

    fun incStepCompleted(
        step: String,
        service: String,
        status: String,
    ) {
        try {
            stepCompleted?.add(
                1,
                Attributes.of(
                    AttributeKey.stringKey("step"),
                    step,
                    AttributeKey.stringKey("service"),
                    service,
                    AttributeKey.stringKey("status"),
                    status,
                ),
            )
        } catch (_: Exception) {
        }
    }

    fun incRetry(
        step: String,
        reason: String,
    ) {
        try {
            stepRetries?.add(
                1,
                Attributes.of(
                    AttributeKey.stringKey("step"),
                    step,
                    AttributeKey.stringKey("reason"),
                    reason,
                ),
            )
        } catch (_: Exception) {
        }
    }

    fun incArtifact(
        type: String,
        bytes: Long = 1,
    ) {
        try {
            artifactsCreated?.add(1, Attributes.of(AttributeKey.stringKey("type"), type))
            artifactBytes?.add(bytes, Attributes.of(AttributeKey.stringKey("type"), type))
        } catch (_: Exception) {
        }
    }

    fun recordOcrConfidence(
        conf: Double,
        mode: String = "full",
    ) {
        try {
            ocrConfidence?.record(conf, Attributes.of(AttributeKey.stringKey("mode"), mode))
        } catch (_: Exception) {
        }
    }

    fun setActiveRuns(n: Long) {
        activeRunsGauge.set(n)
    }

    fun setSseConnections(n: Long) {
        sseConnectionsGauge.set(n)
    }

    fun recordKafkaLag(
        lag: Long,
        service: String,
        topic: String,
    ) {
        try {
            kafkaLag?.record(
                lag.toDouble(),
                Attributes.of(
                    AttributeKey.stringKey("service"),
                    service,
                    AttributeKey.stringKey("topic"),
                    topic,
                ),
            )
        } catch (_: Exception) {
        }
    }
}
