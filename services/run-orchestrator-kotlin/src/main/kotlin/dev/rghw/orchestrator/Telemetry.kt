package dev.rghw.orchestrator

import io.opentelemetry.api.common.AttributeKey
import io.opentelemetry.api.common.Attributes
import io.opentelemetry.api.logs.Logger
import io.opentelemetry.api.logs.Severity
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator
import io.opentelemetry.context.propagation.ContextPropagators
import io.opentelemetry.exporter.otlp.logs.OtlpGrpcLogRecordExporter
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter
import io.opentelemetry.sdk.OpenTelemetrySdk
import io.opentelemetry.sdk.logs.SdkLoggerProvider
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor
import io.opentelemetry.sdk.resources.Resource
import io.opentelemetry.sdk.trace.SdkTracerProvider
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor
import java.time.Duration
import java.util.concurrent.TimeUnit

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

    fun endpoint(lookup: (String) -> String? = System::getenv): String =
        lookup("OTEL_EXPORTER_OTLP_ENDPOINT")?.takeIf { it.isNotBlank() } ?: DEFAULT_ENDPOINT

    /**
     * Builds and globally registers the tracer and logger providers. Returns
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
                    .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
                    .buildAndRegisterGlobal()
            sdk = started
            logger = started.logsBridge.get(SCOPE_NAME)
            Runtime.getRuntime().addShutdownHook(Thread(::shutdown, "otel-shutdown"))
            started
                .getTracer(SCOPE_NAME)
                .spanBuilder("orchestrator.startup")
                .startSpan()
                .end()
            log(Severity.INFO, "orchestrator telemetry started", Attributes.of(endpointKey, endpoint))
            true
        } catch (e: Exception) {
            System.err.println("[otel] telemetry disabled: ${e.javaClass.simpleName}")
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
}
