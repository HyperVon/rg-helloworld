package telemetry

import (
	"context"
	"testing"
	"time"

	"go.opentelemetry.io/otel/log"
)

func TestGrpcTargetStripsSchemeAndDefaults(t *testing.T) {
	cases := map[string]string{
		"":   "otel-collector.rube-goldberg:4317",
		"  ": "otel-collector.rube-goldberg:4317",
		"http://otel-collector.rube-goldberg:4317": "otel-collector.rube-goldberg:4317",
		"https://collector.example:4317/":          "collector.example:4317",
		"127.0.0.1:4317":                           "127.0.0.1:4317",
	}
	for endpoint, want := range cases {
		if got := grpcTarget(endpoint); got != want {
			t.Errorf("grpcTarget(%q) = %q, want %q", endpoint, got, want)
		}
	}
}

func TestInitExportsAndShutsDownWithoutCollector(t *testing.T) {
	shutdownTimeout = 100 * time.Millisecond
	t.Cleanup(func() { shutdownTimeout = 2 * time.Second })

	ctx := context.Background()
	shutdown := Init(ctx, "127.0.0.1:1")
	if shutdown == nil {
		t.Fatal("Init returned nil shutdown")
	}
	Info(ctx, "started", log.String("version", "test"))
	Error(ctx, "handled failure", log.String("error", "boom"))
	shutdown()
}

func TestEmitWithoutInitIsSafe(t *testing.T) {
	Info(context.Background(), "no provider")
	Error(context.Background(), "no provider")
}
