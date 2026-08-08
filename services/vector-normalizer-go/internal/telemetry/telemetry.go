// Package telemetry exports vector-normalizer traces and logs to an
// OpenTelemetry collector over OTLP/gRPC.
package telemetry

import (
	"context"
	"strings"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/log"
	"go.opentelemetry.io/otel/log/global"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"

	"rghw.dev/vector-normalizer/internal/version"
)

// ServiceName is the resource service.name reported for every signal.
const ServiceName = "vector-normalizer"

// DefaultEndpoint is the in-cluster collector address used when
// OTEL_EXPORTER_OTLP_ENDPOINT is unset.
const DefaultEndpoint = "http://otel-collector.rube-goldberg:4317"

const scopeName = "rghw.dev/vector-normalizer"

// shutdownTimeout bounds the final flush so an unreachable collector cannot
// stall service exit; tests override it.
var shutdownTimeout = 2 * time.Second

// Init installs global tracer and logger providers exporting over OTLP/gRPC
// to endpoint, or to DefaultEndpoint when endpoint is empty. Export is best
// effort: a signal whose exporter cannot be created is left disabled and the
// service runs on. The returned function flushes and stops both providers and
// is always safe to call.
func Init(ctx context.Context, endpoint string) func() {
	target := grpcTarget(endpoint)
	res := resource.NewWithAttributes(semconv.SchemaURL,
		semconv.ServiceName(ServiceName),
		semconv.ServiceVersion(version.Version),
	)
	stops := make([]func(context.Context) error, 0, 2)

	if exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(target),
		otlptracegrpc.WithInsecure(),
	); err == nil {
		provider := sdktrace.NewTracerProvider(
			sdktrace.WithResource(res),
			sdktrace.WithBatcher(exporter),
		)
		otel.SetTracerProvider(provider)
		stops = append(stops, provider.Shutdown)
	}

	if exporter, err := otlploggrpc.New(ctx,
		otlploggrpc.WithEndpoint(target),
		otlploggrpc.WithInsecure(),
	); err == nil {
		provider := sdklog.NewLoggerProvider(
			sdklog.WithResource(res),
			sdklog.WithProcessor(sdklog.NewBatchProcessor(exporter)),
		)
		global.SetLoggerProvider(provider)
		stops = append(stops, provider.Shutdown)
	}

	otel.SetTextMapPropagator(propagation.TraceContext{})

	return func() {
		ctx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		for _, stop := range stops {
			_ = stop(ctx)
		}
	}
}

// Info emits an informational log record. Bodies and attributes must describe
// only control flow: never the requested plaintext, expected characters,
// glyph geometry, or image bytes.
func Info(ctx context.Context, body string, attrs ...log.KeyValue) {
	emit(ctx, log.SeverityInfo, "INFO", body, attrs...)
}

// Error emits an error log record under the same payload restrictions as Info.
func Error(ctx context.Context, body string, attrs ...log.KeyValue) {
	emit(ctx, log.SeverityError, "ERROR", body, attrs...)
}

func emit(ctx context.Context, severity log.Severity, severityText, body string, attrs ...log.KeyValue) {
	var record log.Record
	record.SetTimestamp(time.Now())
	record.SetSeverity(severity)
	record.SetSeverityText(severityText)
	record.SetBody(log.StringValue(body))
	record.AddAttributes(attrs...)
	global.GetLoggerProvider().Logger(scopeName).Emit(ctx, record)
}

func grpcTarget(endpoint string) string {
	target := strings.TrimSpace(endpoint)
	if target == "" {
		target = DefaultEndpoint
	}
	if i := strings.Index(target, "://"); i >= 0 {
		target = target[i+3:]
	}
	return strings.TrimSuffix(target, "/")
}
