package observability

import (
	"context"
	"fmt"
	"log/slog"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"
)

const CollectorEndpoint = "http://otel-collector.rube-goldberg:4318"

func InitTracer(ctx context.Context, serviceName string) (func(), error) {
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("0.5.0-milestone11"),
		),
	)
	if err != nil {
		return func() {}, fmt.Errorf("creating resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)
	otel.SetTracerProvider(tp)
	shutdown := func() {
		_ = tp.Shutdown(context.Background())
	}
	return shutdown, nil
}

func FormatTraceId(traceId string) string {
	if len(traceId) < 32 {
		pad := make([]byte, 32-len(traceId))
		for i := range pad {
			pad[i] = '0'
		}
		return traceId + string(pad)
	}
	return traceId[:32]
}

func FormatSpanId(spanId string) string {
	if len(spanId) < 16 {
		pad := make([]byte, 16-len(spanId))
		for i := range pad {
			pad[i] = '0'
		}
		return spanId + string(pad)
	}
	return spanId[:16]
}

func InjectTraceparent(traceId, spanId string, traceFlags byte) string {
	return fmt.Sprintf("00-%s-%s-%02x", FormatTraceId(traceId), FormatSpanId(spanId), traceFlags)
}

func LogFields(runId, stepId, traceId, spanId string) []any {
	fields := []any{
		slog.String("service", "rghw"),
		slog.String("runId", runId),
	}
	if stepId != "" {
		fields = append(fields, slog.String("stepId", stepId))
	}
	if traceId != "" {
		fields = append(fields, slog.String("traceId", traceId))
	}
	if spanId != "" {
		fields = append(fields, slog.String("spanId", spanId))
	}
	return fields
}
