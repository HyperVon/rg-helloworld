package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"

	"rghw.dev/vector-normalizer/internal/kafka"
	"rghw.dev/vector-normalizer/internal/rasterclient"
	"rghw.dev/vector-normalizer/internal/s3store"
	"rghw.dev/vector-normalizer/internal/version"
	"rghw.dev/vector-normalizer/internal/worker"
)

var exit = os.Exit

func main() {
	exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) >= 1 && args[0] == "version" {
		fmt.Fprintf(stdout, "vector-normalizer %s\n", version.Version)
		if len(args) > 1 {
			fmt.Fprintln(stderr, "usage: vector-normalizer version")
			return 1
		}
		return 0
	}
	if len(args) >= 1 && args[0] == "--once" {
		return runOnce(args[1:], os.Stdin, stdout, stderr)
	}
	if len(args) >= 1 && args[0] == "run" {
		return runWorker(stderr)
	}
	fmt.Fprintln(stderr, "vector-normalizer: unknown command")
	fmt.Fprintln(stderr, "usage: vector-normalizer version | run | --once [--emit-artifacts-to DIR]")
	return 1
}

// runOnce transforms a single GeometryExpanded CloudEvent read from stdin
// into the VectorNormalized event on stdout; with --emit-artifacts-to the
// normalized JSON and SVG artifacts are also written to a directory. With
// --rasterizer-url the drawable glyph is additionally rasterized over gRPC
// and the GlyphRasterized event is emitted on stdout.
func runOnce(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	artifactsDir := ""
	rasterizerURL := ""
	for i := 0; i < len(args); i++ {
		if args[i] == "--emit-artifacts-to" && i+1 < len(args) {
			artifactsDir = args[i+1]
			i++
		}
		if args[i] == "--rasterizer-url" && i+1 < len(args) {
			rasterizerURL = args[i+1]
			i++
		}
	}
	input, err := io.ReadAll(stdin)
	if err != nil {
		fmt.Fprintf(stderr, "vector-normalizer: read stdin: %v\n", err)
		return 1
	}
	bucket := envOr("MINIO_BUCKET", "rube-goldberg-artifacts")
	config := worker.Config{Bucket: bucket}
	if rasterizerURL != "" {
		client, err := rasterclient.New(rasterizerURL)
		if err != nil {
			fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			return 1
		}
		defer client.Close()
		config.Renderer = client
	}
	outcome, err := worker.Process(context.Background(), string(input), config)
	if err != nil {
		fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
		return 1
	}
	if artifactsDir != "" {
		if err := os.MkdirAll(artifactsDir, 0o755); err != nil {
			fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			return 1
		}
		write := func(key, content string) {
			name := filepath.Base(key)
			if err := os.WriteFile(filepath.Join(artifactsDir, name), []byte(content), 0o644); err != nil {
				fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			}
		}
		write(outcome.NormalizedKey, outcome.NormalizedJSON)
		write(outcome.SvgKey, outcome.SvgContent)
	}
	fmt.Fprintln(stdout, outcome.OutputEvent)
	if outcome.RasterEvent != "" {
		fmt.Fprintln(stdout, outcome.RasterEvent)
	}
	return 0
}

// runWorker runs the consume-normalize-store-publish loop.
func runWorker(stderr io.Writer) int {
	ctx := context.Background()
	transport, err := kafka.New(envOr("KAFKA_BOOTSTRAP", "localhost:9092"),
		envOr("KAFKA_GROUP_ID", "vector-normalizer"),
		envOr("NORMALIZER_INPUT_TOPIC", "rg.geometry-expanded.v1"))
	if err != nil {
		fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
		return 1
	}
	defer transport.Close()

	store, err := s3store.New(envOr("MINIO_ENDPOINT", "localhost:9000"),
		envOr("MINIO_ACCESS_KEY", "minioadmin"), envOr("MINIO_SECRET_KEY", "minioadmin"), false)
	if err != nil {
		fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
		return 1
	}

	config := worker.Config{
		OutputTopic:     envOr("NORMALIZER_OUTPUT_TOPIC", "rg.glyph-normalized.v1"),
		RasterizedTopic: envOr("NORMALIZER_RASTERIZED_TOPIC", "rg.glyph-rasterized.v1"),
		Bucket:          envOr("MINIO_BUCKET", "rube-goldberg-artifacts"),
	}
	if addr := envOr("RASTERIZER_ADDR", ""); addr != "" {
		client, err := rasterclient.New(addr)
		if err != nil {
			fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			return 1
		}
		defer client.Close()
		config.Renderer = client
	}
	return workerLoop(ctx, transport, store, config, stderr)
}

// retryDelay is the backoff between failed iterations; tests override it.
var retryDelay = time.Second

// workerLoop polls, processes, stores, publishes, and commits until the
// context is canceled. Failures are logged and retried (at-least-once: an
// uncommitted offset is redelivered after a restart).
func workerLoop(ctx context.Context, transport kafka.Transport, store s3store.Store,
	config worker.Config, stderr io.Writer) int {
	loop := worker.New(transport, store, config)
	for {
		select {
		case <-ctx.Done():
			return 0
		default:
		}
		processed, err := loop.ProcessOne(ctx)
		if err != nil {
			fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			select {
			case <-ctx.Done():
				return 0
			case <-time.After(retryDelay):
			}
			continue
		}
		if processed {
			if err := transport.Commit(ctx); err != nil {
				fmt.Fprintf(stderr, "vector-normalizer: %v\n", err)
			}
		}
	}
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
