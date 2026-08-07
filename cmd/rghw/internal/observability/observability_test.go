package observability

import (
	"strings"
	"testing"
)

func TestFormatTraceId(t *testing.T) {
	result := FormatTraceId("abc")
	if len(result) != 32 {
		t.Fatalf("expected length 32, got %d", len(result))
	}
	if !strings.HasPrefix(result, "abc") {
		t.Fatalf("expected prefix 'abc', got %s", result)
	}
}

func TestFormatTraceIdLongInput(t *testing.T) {
	result := FormatTraceId("abcdef1234567890abcdef1234567890abcdef")
	if len(result) != 32 {
		t.Fatalf("expected length 32, got %d", len(result))
	}
	if result != "abcdef1234567890abcdef1234567890" {
		t.Fatalf("unexpected result: %s", result)
	}
}

func TestFormatSpanId(t *testing.T) {
	result := FormatSpanId("def")
	if len(result) != 16 {
		t.Fatalf("expected length 16, got %d", len(result))
	}
	if !strings.HasPrefix(result, "def") {
		t.Fatalf("expected prefix 'def', got %s", result)
	}
}

func TestFormatSpanIdLongInput(t *testing.T) {
	result := FormatSpanId("deadbeefdeadbeefdeadbeef")
	if len(result) != 16 {
		t.Fatalf("expected length 16, got %d", len(result))
	}
	if result != "deadbeefdeadbeef" {
		t.Fatalf("unexpected result: %s", result)
	}
}

func TestInjectTraceparent(t *testing.T) {
	result := InjectTraceparent("abcdef1234567890abcdef1234567890", "deadbeef", 1)
	parts := strings.Split(result, "-")
	if len(parts) != 4 {
		t.Fatalf("expected 4 parts, got %d", len(parts))
	}
	if parts[0] != "00" {
		t.Fatalf("expected version '00', got %s", parts[0])
	}
	if len(parts[1]) != 32 {
		t.Fatalf("expected trace ID length 32, got %d", len(parts[1]))
	}
	if len(parts[2]) != 16 {
		t.Fatalf("expected span ID length 16, got %d", len(parts[2]))
	}
	if parts[3] != "01" {
		t.Fatalf("expected trace flags '01', got %s", parts[3])
	}
}

func TestInjectTraceparentZeroFlags(t *testing.T) {
	result := InjectTraceparent("trace123", "span456", 0)
	if !strings.HasSuffix(result, "-00") {
		t.Fatalf("expected trace flags '00', got %s", result)
	}
}

func TestLogFields(t *testing.T) {
	fields := LogFields("run-1", "step-1", "trace-abc", "span-def")
	if len(fields) != 5 {
		t.Fatalf("expected 4 fields, got %d", len(fields))
	}
}

func TestLogFieldsMinimal(t *testing.T) {
	fields := LogFields("run-1", "", "", "")
	if len(fields) != 2 {
		t.Fatalf("expected 2 fields, got %d", len(fields))
	}
}

func TestInitTracer(t *testing.T) {
	ctx := t.Context()
	shutdown, err := InitTracer(ctx, "test-service")
	if err != nil {
		t.Fatalf("InitTracer failed: %v", err)
	}
	shutdown()
}

func TestCollectorEndpoint(t *testing.T) {
	if CollectorEndpoint != "http://otel-collector.rube-goldberg:4318" {
		t.Fatalf("unexpected CollectorEndpoint: %s", CollectorEndpoint)
	}
}
