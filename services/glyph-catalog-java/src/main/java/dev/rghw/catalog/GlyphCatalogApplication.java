package dev.rghw.catalog;

import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.logs.Severity;
import io.opentelemetry.api.trace.propagation.W3CTraceContextPropagator;
import io.opentelemetry.context.propagation.ContextPropagators;
import io.opentelemetry.exporter.otlp.logs.OtlpGrpcLogRecordExporter;
import io.opentelemetry.exporter.otlp.trace.OtlpGrpcSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.logs.SdkLoggerProvider;
import io.opentelemetry.sdk.logs.export.BatchLogRecordProcessor;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import java.time.Duration;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class GlyphCatalogApplication {

  public static final String SERVICE_NAME = "glyph-catalog";
  public static final String MILESTONE = "0.1.0-milestone4";

  static final String DEFAULT_OTLP_ENDPOINT = "http://otel-collector.rube-goldberg:4317";

  private static final Duration EXPORT_TIMEOUT = Duration.ofSeconds(5);

  private GlyphCatalogApplication() {}

  public static void main(String[] args) {
    if (args.length == 1 && "version".equals(args[0])) {
      System.out.printf("%s %s%n", SERVICE_NAME, GlyphCatalogVersion.VERSION);
      return;
    }
    initTelemetry(System.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"));
    SpringApplication.run(GlyphCatalogApplication.class, args);
  }

  static void initTelemetry(String endpointOverride) {
    String endpoint =
        endpointOverride == null || endpointOverride.isBlank()
            ? DEFAULT_OTLP_ENDPOINT
            : endpointOverride;
    try {
      Resource resource =
          Resource.getDefault()
              .merge(
                  Resource.create(
                      Attributes.of(
                          AttributeKey.stringKey("service.name"),
                          SERVICE_NAME,
                          AttributeKey.stringKey("service.version"),
                          GlyphCatalogVersion.VERSION)));
      SdkTracerProvider tracerProvider =
          SdkTracerProvider.builder()
              .setResource(resource)
              .addSpanProcessor(
                  BatchSpanProcessor.builder(
                          OtlpGrpcSpanExporter.builder()
                              .setEndpoint(endpoint)
                              .setTimeout(EXPORT_TIMEOUT)
                              .build())
                      .build())
              .build();
      SdkLoggerProvider loggerProvider =
          SdkLoggerProvider.builder()
              .setResource(resource)
              .addLogRecordProcessor(
                  BatchLogRecordProcessor.builder(
                          OtlpGrpcLogRecordExporter.builder()
                              .setEndpoint(endpoint)
                              .setTimeout(EXPORT_TIMEOUT)
                              .build())
                      .build())
              .build();
      OpenTelemetrySdk sdk =
          OpenTelemetrySdk.builder()
              .setResource(resource)
              .setTracerProvider(tracerProvider)
              .setLoggerProvider(loggerProvider)
              .setPropagators(ContextPropagators.create(W3CTraceContextPropagator.getInstance()))
              .buildAndRegisterGlobal();
      Runtime.getRuntime().addShutdownHook(new Thread(sdk::close, "otel-shutdown"));
      sdk.getSdkLoggerProvider()
          .get(SERVICE_NAME)
          .logRecordBuilder()
          .setSeverity(Severity.INFO)
          .setBody("service started")
          .setAttribute(AttributeKey.stringKey("service.version"), GlyphCatalogVersion.VERSION)
          .setAttribute(AttributeKey.stringKey("otlp.endpoint"), endpoint)
          .emit();
    } catch (RuntimeException | LinkageError e) {
      System.err.printf(
          "%s: OpenTelemetry export disabled (%s): %s%n",
          SERVICE_NAME, endpoint, e.getClass().getSimpleName());
    }
  }
}
