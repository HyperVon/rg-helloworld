package main

import (
	"bytes"
	"context"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"google.golang.org/grpc"

	rgProto "rghw.dev/vector-normalizer/internal/rasterproto"
	"rghw.dev/vector-normalizer/internal/worker"
)

const geometryEventForMain = `{
  "specversion": "1.0",
  "id": "11111111-1111-4111-8111-111111111111",
  "source": "geometry-engine",
  "type": "rg.geometry-expanded.v1",
  "subject": "runs/22222222-2222-4222-8222-222222222222/glyphs/55555555-5555-4555-8555-555555555555",
  "time": "2026-08-05T00:00:00.000Z",
  "datacontenttype": "application/json",
  "correlationid": "22222222-2222-4222-8222-222222222222",
  "causationid": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "data": {
    "runId": "22222222-2222-4222-8222-222222222222",
    "stepId": "44444444-4444-4444-8444-444444444444",
    "glyphInstanceId": "55555555-5555-4555-8555-555555555555",
    "position": 0,
    "attempt": 1,
    "inputMaturity": 10,
    "outputMaturity": 20,
    "inputArtifacts": ["runs/22222222-2222-4222-8222-222222222222/glyphs/0-55555555-5555-4555-8555-555555555555/geometry-attempt-1-abc.json"],
    "outputArtifacts": [],
    "transformation": {"name": "expand-geometry", "version": "1.0.0"},
    "geometry": {
      "kind": "DRAWABLE_GEOMETRY",
      "segments": [
        {"x1": 0.1, "y1": 0.0, "x2": 0.1, "y2": 1.0},
        {"x1": 0.9, "y1": 0.0, "x2": 0.9, "y2": 1.0},
        {"x1": 0.1, "y1": 0.5, "x2": 0.9, "y2": 0.5}
      ],
      "boundingBox": {"xMin": 0.1, "yMin": 0.0, "xMax": 0.9, "yMax": 1.0},
      "advanceWidth": 1.0,
      "totalLength": 2.8,
      "segmentCount": 3,
      "geometrySha256": "28f75f5ee107f08144aa9a9ac1eb56c82c58336d4d99f7dab3da91b009d43636"
    }
  }
}`

const versionPrefix = "vector-normalizer 0.2.0-milestone6"

func TestVersionCommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"version"}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("exit code = %d, want 0", code)
	}
	if !strings.HasPrefix(stdout.String(), versionPrefix) {
		t.Fatalf("stdout = %q, want prefix %q", stdout.String(), versionPrefix)
	}
	if stderr.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", stderr.String())
	}
}

func TestVersionWithExtraArgsFails(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"version", "extra"}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "usage:") {
		t.Fatalf("stderr = %q, want usage line", stderr.String())
	}
}

func TestUnknownCommandUsesStderr(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := run([]string{"bogus"}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("exit code = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "unknown command") {
		t.Fatalf("stderr = %q, want unknown command", stderr.String())
	}
}

func TestOnceMode(t *testing.T) {
	var stdout, stderr bytes.Buffer
	input := strings.NewReader(`{"specversion":"1.0","id":"11111111-1111-4111-8111-111111111111","source":"geometry-engine","type":"rg.geometry-expanded.v1","time":"2026-08-05T00:00:00.000Z","datacontenttype":"application/json","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":0,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"transformation":{"name":"expand-geometry","version":"1.0.0"},"geometry":{"kind":"DRAWABLE_GEOMETRY","segments":[{"x1":0.1,"y1":0.0,"x2":0.1,"y2":1.0}],"advanceWidth":1.0,"totalLength":1.0,"geometrySha256":"abc"}}}`)
	code := runOnce([]string{}, input, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("runOnce exit = %d, stderr = %q", code, stderr.String())
	}
	out := stdout.String()
	if !strings.Contains(out, `"type":"rg.glyph-normalized.v1"`) {
		t.Fatalf("output = %q, want normalized event", out)
	}
	if !strings.Contains(out, `"outputMaturity":30`) {
		t.Fatalf("output = %q, want maturity 30", out)
	}
	if strings.Contains(out, "expectedCharacter") {
		t.Fatalf("output contains prohibited field: %q", out)
	}
}

func TestOnceModeEmitsArtifacts(t *testing.T) {
	dir := t.TempDir()
	var stdout, stderr bytes.Buffer
	code := runOnce([]string{"--emit-artifacts-to", dir}, strings.NewReader(
		`{"specversion":"1.0","id":"11111111-1111-4111-8111-111111111111","type":"rg.geometry-expanded.v1","datacontenttype":"application/json","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":0,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"transformation":{"name":"expand-geometry","version":"1.0.0"},"geometry":{"kind":"GAP_GEOMETRY","segments":[],"advanceWidth":0.6,"totalLength":0.0,"geometrySha256":"abc"}}}`),
		&stdout, &stderr)
	if code != 0 {
		t.Fatalf("runOnce exit = %d, stderr = %q", code, stderr.String())
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("ReadDir: %v", err)
	}
	if len(entries) != 2 {
		t.Fatalf("artifacts = %d, want 2", len(entries))
	}
	names := []string{entries[0].Name(), entries[1].Name()}
	joined := strings.Join(names, " ")
	if !strings.Contains(joined, ".json") || !strings.Contains(joined, ".svg") {
		t.Fatalf("artifact names = %v", names)
	}
	svg, err := os.ReadFile(filepath.Join(dir, names[0]))
	if err != nil {
		t.Fatalf("ReadFile: %v", err)
	}
	if strings.Contains(string(svg), "<text") {
		t.Fatalf("SVG contains text: %s", svg)
	}
}

func TestOnceModeBadInput(t *testing.T) {
	var stdout, stderr bytes.Buffer
	code := runOnce([]string{}, strings.NewReader("not json"), &stdout, &stderr)
	if code != 1 {
		t.Fatalf("runOnce exit = %d, want 1", code)
	}
}

func TestRunWorkerFailsWithoutMinio(t *testing.T) {
	t.Setenv("MINIO_ENDPOINT", "not a host")
	var stdout, stderr bytes.Buffer
	code := run([]string{"run"}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("run(run) = %d, want 1; stderr=%q", code, stderr.String())
	}
	if !strings.Contains(stderr.String(), "vector-normalizer:") {
		t.Fatalf("stderr = %q", stderr.String())
	}
}

func TestRunOnceUsesEnvBucket(t *testing.T) {
	t.Setenv("MINIO_BUCKET", "env-bucket")
	var stdout, stderr bytes.Buffer
	input := strings.NewReader(`{"specversion":"1.0","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":0,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"geometry":{"kind":"GAP_GEOMETRY","segments":[],"advanceWidth":0.6,"totalLength":0.0,"geometrySha256":"abc"}}}`)
	if code := runOnce([]string{}, input, &stdout, &stderr); code != 0 {
		t.Fatalf("runOnce = %d, stderr=%q", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), `"outputMaturity":30`) {
		t.Fatalf("stdout = %q", stdout.String())
	}
}

func TestRunOnceUnwritableArtifactsDir(t *testing.T) {
	file := filepath.Join(t.TempDir(), "blocked")
	if err := os.WriteFile(file, []byte("x"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	var stdout, stderr bytes.Buffer
	input := strings.NewReader(`{"specversion":"1.0","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":0,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"geometry":{"kind":"GAP_GEOMETRY","segments":[],"advanceWidth":0.6,"totalLength":0.0,"geometrySha256":"abc"}}}`)
	if code := runOnce([]string{"--emit-artifacts-to", file}, input, &stdout, &stderr); code != 1 {
		t.Fatalf("runOnce = %d, want 1; stderr=%q", code, stderr.String())
	}
}

type exitSignal struct{ code int }

// fakeLoopTransport is a minimal kafka.Transport for workerLoop tests.
type fakeLoopTransport struct {
	pollResult  string
	pollOK      bool
	pollErr     bool
	commitErr   bool
	commitCalls int
	produceErr  bool
}

func (f *fakeLoopTransport) Poll(context.Context) (string, bool) {
	if f.pollErr {
		return "", false
	}
	return f.pollResult, f.pollOK
}

func (f *fakeLoopTransport) Produce(context.Context, string, string, string) error {
	if f.produceErr {
		return context.DeadlineExceeded
	}
	return nil
}

func (f *fakeLoopTransport) Commit(context.Context) error {
	f.commitCalls++
	if f.commitErr {
		return context.DeadlineExceeded
	}
	return nil
}

func (f *fakeLoopTransport) Close() {}

type fakeLoopStore struct {
	fail bool
}

func (f *fakeLoopStore) PutObject(context.Context, string, string, []byte, string) error {
	if f.fail {
		return context.DeadlineExceeded
	}
	return nil
}

const validGeometryEvent = `{"specversion":"1.0","datacontenttype":"application/json","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":0,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"geometry":{"kind":"GAP_GEOMETRY","segments":[],"advanceWidth":0.6,"totalLength":0.0,"geometrySha256":"abc"}}}`

func TestWorkerLoopProcessesAndCommits(t *testing.T) {
	old := retryDelay
	retryDelay = time.Millisecond
	defer func() { retryDelay = old }()

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	transport := &fakeLoopTransport{pollResult: validGeometryEvent, pollOK: true}
	var stderr bytes.Buffer
	code := workerLoop(ctx, transport, &fakeLoopStore{},
		worker.Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"}, &stderr)
	if code != 0 {
		t.Fatalf("workerLoop = %d, stderr = %q", code, stderr.String())
	}
	if transport.commitCalls == 0 {
		t.Fatal("commit was not called after processing")
	}
}

func TestWorkerLoopPollTimeoutLoops(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	transport := &fakeLoopTransport{pollOK: false}
	var stderr bytes.Buffer
	if code := workerLoop(ctx, transport, &fakeLoopStore{},
		worker.Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"}, &stderr); code != 0 {
		t.Fatalf("workerLoop = %d", code)
	}
	if transport.commitCalls != 0 {
		t.Fatal("commit must not run on poll timeout")
	}
}

func TestWorkerLoopFailureRetries(t *testing.T) {
	old := retryDelay
	retryDelay = time.Millisecond
	defer func() { retryDelay = old }()

	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	transport := &fakeLoopTransport{pollResult: validGeometryEvent, pollOK: true}
	var stderr bytes.Buffer
	code := workerLoop(ctx, transport, &fakeLoopStore{fail: true},
		worker.Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"}, &stderr)
	if code != 0 {
		t.Fatalf("workerLoop = %d", code)
	}
	if !strings.Contains(stderr.String(), "vector-normalizer:") {
		t.Fatalf("stderr = %q, want error log", stderr.String())
	}
}

func TestWorkerLoopCommitFailure(t *testing.T) {
	old := retryDelay
	retryDelay = time.Millisecond
	defer func() { retryDelay = old }()

	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	transport := &fakeLoopTransport{pollResult: validGeometryEvent, pollOK: true, commitErr: true}
	var stderr bytes.Buffer
	code := workerLoop(ctx, transport, &fakeLoopStore{},
		worker.Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"}, &stderr)
	if code != 0 {
		t.Fatalf("workerLoop = %d", code)
	}
	if !strings.Contains(stderr.String(), "vector-normalizer:") {
		t.Fatalf("stderr = %q, want commit error log", stderr.String())
	}
}

func TestWorkerLoopProduceFailure(t *testing.T) {
	old := retryDelay
	retryDelay = time.Millisecond
	defer func() { retryDelay = old }()

	ctx, cancel := context.WithTimeout(context.Background(), 150*time.Millisecond)
	defer cancel()
	transport := &fakeLoopTransport{pollResult: validGeometryEvent, pollOK: true, produceErr: true}
	var stderr bytes.Buffer
	code := workerLoop(ctx, transport, &fakeLoopStore{},
		worker.Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"}, &stderr)
	if code != 0 {
		t.Fatalf("workerLoop = %d", code)
	}
	if !strings.Contains(stderr.String(), "vector-normalizer:") {
		t.Fatalf("stderr = %q, want produce error log", stderr.String())
	}
}

func TestMainInvocation(t *testing.T) {
	if os.Getenv("VECTOR_NORMALIZER_MAIN_HELPER") == "1" {
		os.Args = []string{"vector-normalizer", "version"}
		exit = func(code int) { panic(exitSignal{code: code}) }
		defer func() {
			if r := recover(); r != nil {
				if s, ok := r.(exitSignal); !ok || s.code != 0 {
					panic(r)
				}
			}
		}()
		main()
		return
	}
	cmd := exec.Command(os.Args[0], "-test.run=TestMainInvocation")
	cmd.Env = append(os.Environ(), "VECTOR_NORMALIZER_MAIN_HELPER=1")
	if profile := os.Getenv("RGHW_CHILD_COVER"); profile != "" {
		cmd.Args = append(cmd.Args, "-test.coverprofile="+profile)
	}
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("main() exited with error: %v (output: %q)", err, out)
	}
	if !strings.HasPrefix(string(out), versionPrefix+"\n") {
		t.Fatalf("main() output = %q, want prefix %q", out, versionPrefix+"\n")
	}
}

type fakeRasterizerForMain struct {
	rgProto.UnimplementedRasterizerServer
}

func (f *fakeRasterizerForMain) RenderGlyph(_ context.Context, _ *rgProto.RenderGlyphRequest) (*rgProto.RenderGlyphResponse, error) {
	return &rgProto.RenderGlyphResponse{
		ObjectKey:   "runs/r/glyphs/0-g/raster-attempt-1-op.png",
		Sha256:      "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
		Width:       64,
		Height:      96,
		ByteCount:   1234,
		ContentType: "image/png",
	}, nil
}

func TestOnceModeWithRasterizer(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	server := grpc.NewServer()
	rgProto.RegisterRasterizerServer(server, &fakeRasterizerForMain{})
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(server.Stop)

	var stdout, stderr bytes.Buffer
	input := strings.NewReader(geometryEventForMain)
	code := runOnce([]string{"--rasterizer-url", listener.Addr().String()}, input, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("runOnce = %d, stderr=%q", code, stderr.String())
	}
	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	if len(lines) != 2 {
		t.Fatalf("stdout has %d lines, want 2 (normalized + rasterized): %q", len(lines), stdout.String())
	}
	if !strings.Contains(lines[1], `"type":"rg.glyph-rasterized.v1"`) ||
		!strings.Contains(lines[1], `"outputMaturity":40`) {
		t.Fatalf("rasterized event missing: %q", lines[1])
	}
	if worker.ContainsProhibitedField(lines[1]) {
		t.Fatal("rasterized event contains a prohibited field")
	}
}

func TestOnceModeRasterizerUnreachable(t *testing.T) {
	var stdout, stderr bytes.Buffer
	input := strings.NewReader(geometryEventForMain)
	code := runOnce([]string{"--rasterizer-url", "127.0.0.1:1"}, input, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("runOnce = %d, want 1; stderr=%q", code, stderr.String())
	}
	if !strings.Contains(stderr.String(), "rasterize glyph") {
		t.Fatalf("stderr = %q", stderr.String())
	}
}

func TestRunWorkerWithRasterizerAddrFailsWithoutMinio(t *testing.T) {
	t.Setenv("MINIO_ENDPOINT", "not a host")
	t.Setenv("RASTERIZER_ADDR", "127.0.0.1:50051")
	var stdout, stderr bytes.Buffer
	code := run([]string{"run"}, &stdout, &stderr)
	if code != 1 {
		t.Fatalf("run(run) = %d, want 1; stderr=%q", code, stderr.String())
	}
}
