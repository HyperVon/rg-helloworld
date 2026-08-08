package worker

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"rghw.dev/vector-normalizer/internal/rasterproto"
)

type fakeRenderer struct {
	resp  *rasterproto.RenderGlyphResponse
	err   error
	calls int
	got   *rasterproto.RenderGlyphRequest
}

func (f *fakeRenderer) Render(_ context.Context, req *rasterproto.RenderGlyphRequest) (*rasterproto.RenderGlyphResponse, error) {
	f.calls++
	f.got = req
	if f.err != nil {
		return nil, f.err
	}
	return f.resp, nil
}

func rasterResponse() *rasterproto.RenderGlyphResponse {
	return &rasterproto.RenderGlyphResponse{
		ArtifactId:  "6a4e9c0e-4f6e-4d1c-9b2a-2eaa99d7afaf",
		ObjectKey:   "runs/22222222-2222-4222-8222-222222222222/glyphs/0-55555555-5555-4555-8555-555555555555/raster-attempt-1-op.png",
		Sha256:      "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
		Width:       64,
		Height:      96,
		ByteCount:   1234,
		ContentType: "image/png",
	}
}

func gapFixture() string {
	return strings.Replace(geometryEventFixture, `"kind": "DRAWABLE_GEOMETRY"`, `"kind": "GAP_GEOMETRY"`, 1)
}

func TestProcessDrawableEmitsRasterizedEvent(t *testing.T) {
	renderer := &fakeRenderer{resp: rasterResponse()}
	outcome := mustProcess(t, geometryEventFixture, Config{Bucket: "bucket", Renderer: renderer})
	if outcome.RasterEvent == "" {
		t.Fatal("drawable glyph produced no rasterized event")
	}
	if renderer.calls != 1 {
		t.Fatalf("renderer calls = %d, want 1", renderer.calls)
	}

	var event map[string]any
	if err := json.Unmarshal([]byte(outcome.RasterEvent), &event); err != nil {
		t.Fatalf("raster event not JSON: %v", err)
	}
	if event["specversion"] != "1.0" || event["source"] != "vector-normalizer" {
		t.Fatalf("envelope wrong: %v", event)
	}
	if event["type"] != "rg.glyph-rasterized.v1" {
		t.Fatalf("type = %v", event["type"])
	}
	if event["causationid"] != "11111111-1111-4111-8111-111111111111" {
		t.Fatalf("causationid = %v", event["causationid"])
	}
	if event["correlationid"] != "22222222-2222-4222-8222-222222222222" {
		t.Fatalf("correlationid = %v", event["correlationid"])
	}
	data := event["data"].(map[string]any)
	if data["inputMaturity"] != float64(30) || data["outputMaturity"] != float64(40) {
		t.Fatalf("maturity = %v -> %v, want 30 -> 40", data["inputMaturity"], data["outputMaturity"])
	}
	transformation := data["transformation"].(map[string]any)
	if transformation["name"] != "rasterize-glyph" {
		t.Fatalf("transformation name = %v", transformation["name"])
	}
	if len(data["outputArtifacts"].([]any)) != 1 || data["outputArtifacts"].([]any)[0] != renderer.resp.ObjectKey {
		t.Fatalf("outputArtifacts = %v", data["outputArtifacts"])
	}
	inputArtifacts := data["inputArtifacts"].([]any)
	if len(inputArtifacts) != 2 {
		t.Fatalf("inputArtifacts = %v", inputArtifacts)
	}
	raster := data["raster"].(map[string]any)
	if raster["objectKey"] != renderer.resp.ObjectKey || raster["width"] != float64(64) ||
		raster["height"] != float64(96) || raster["sha256"] != renderer.resp.Sha256 ||
		raster["contentType"] != "image/png" {
		t.Fatalf("raster = %v", raster)
	}
	if raster["pixelDensity"] != 1024.0/96.0 {
		t.Fatalf("pixelDensity = %v", raster["pixelDensity"])
	}
	if ContainsProhibitedField(outcome.RasterEvent) {
		t.Fatal("rasterized event contains a prohibited field")
	}
}

func TestRasterizedEventIdIsDeterministic(t *testing.T) {
	first := mustProcess(t, geometryEventFixture, Config{Bucket: "bucket", Renderer: &fakeRenderer{resp: rasterResponse()}})
	second := mustProcess(t, geometryEventFixture, Config{Bucket: "bucket", Renderer: &fakeRenderer{resp: rasterResponse()}})
	if first.RasterEvent != second.RasterEvent {
		t.Fatal("rasterized events not deterministic")
	}
	var event map[string]any
	if err := json.Unmarshal([]byte(first.RasterEvent), &event); err != nil {
		t.Fatal(err)
	}
	if id, _ := event["id"].(string); len(id) != 36 {
		t.Fatalf("event id = %v, want 36-char UUID", event["id"])
	}
}

func TestRasterizeSendsNormalizedSegmentsAndProfile(t *testing.T) {
	renderer := &fakeRenderer{resp: rasterResponse()}
	outcome := mustProcess(t, geometryEventFixture, Config{Bucket: "bucket", Renderer: renderer})

	var normalizedArtifact map[string]any
	if err := json.Unmarshal([]byte(outcome.NormalizedJSON), &normalizedArtifact); err != nil {
		t.Fatal(err)
	}
	normalizedSegments := normalizedArtifact["normalizedGeometry"].(map[string]any)["segments"].([]any)

	req := renderer.got
	if len(req.Segments) != len(normalizedSegments) {
		t.Fatalf("sent %d segments, want %d", len(req.Segments), len(normalizedSegments))
	}
	first := normalizedSegments[0].(map[string]any)
	if req.Segments[0].X1 != first["x1"] || req.Segments[0].Y1 != first["y1"] ||
		req.Segments[0].X2 != first["x2"] || req.Segments[0].Y2 != first["y2"] {
		t.Fatalf("segment mismatch: got %+v want %v", req.Segments[0], first)
	}
	if req.Canvas.Width != 512 || req.Canvas.Height != 512 || req.Canvas.Baseline != 400 {
		t.Fatalf("canvas = %+v", req.Canvas)
	}
	if req.Profile.StrokeWidth != 140 || !req.Profile.Antialias || req.Profile.LineCap != "round" || req.Profile.Supersampling != 2 {
		t.Fatalf("profile = %+v", req.Profile)
	}
	if req.RunId != "22222222-2222-4222-8222-222222222222" ||
		req.GlyphInstanceId != "55555555-5555-4555-8555-555555555555" || req.Attempt != 1 {
		t.Fatalf("identifiers = %+v", req)
	}
	if len(req.InputArtifactSha256) != 64 {
		t.Fatalf("input artifact sha256 = %q", req.InputArtifactSha256)
	}
}

func TestProcessGapSkipsRasterization(t *testing.T) {
	renderer := &fakeRenderer{resp: rasterResponse()}
	outcome := mustProcess(t, gapFixture(), Config{Bucket: "bucket", Renderer: renderer})
	if outcome.RasterEvent != "" {
		t.Fatal("gap glyph produced a rasterized event")
	}
	if renderer.calls != 0 {
		t.Fatalf("renderer calls = %d, want 0", renderer.calls)
	}
	if outcome.OutputEvent == "" {
		t.Fatal("gap glyph produced no normalized event")
	}
}

func TestProcessWithoutRendererSkipsRasterization(t *testing.T) {
	outcome := mustProcess(t, geometryEventFixture)
	if outcome.RasterEvent != "" {
		t.Fatal("no-renderer run produced a rasterized event")
	}
}

func TestProcessPropagatesRasterizerError(t *testing.T) {
	renderer := &fakeRenderer{err: context.DeadlineExceeded}
	if _, err := Process(context.Background(), geometryEventFixture,
		Config{Bucket: "bucket", Renderer: renderer}); err == nil {
		t.Fatal("Process succeeded despite rasterizer error")
	}
}

func TestProcessOnePublishesBothEvents(t *testing.T) {
	transport := &fakeTransport{messages: []string{geometryEventFixture}}
	store := &fakeStore{}
	renderer := &fakeRenderer{resp: rasterResponse()}
	worker := New(transport, store, Config{
		OutputTopic: outputTopic, RasterizedTopic: rasterizedTopic, Bucket: "bucket", Renderer: renderer,
	})

	processed, err := worker.ProcessOne(context.Background())
	if err != nil || !processed {
		t.Fatalf("ProcessOne = %v, %v", processed, err)
	}
	if len(transport.produced) != 2 {
		t.Fatalf("produced %d records, want 2", len(transport.produced))
	}
	if !strings.HasPrefix(transport.produced[0], "rg.glyph-normalized.v1|") {
		t.Fatalf("first record = %q", transport.produced[0])
	}
	if !strings.HasPrefix(transport.produced[1], "rg.glyph-rasterized.v1|") {
		t.Fatalf("second record = %q", transport.produced[1])
	}
	if len(store.puts) != 2 {
		t.Fatalf("stored %d artifacts, want 2", len(store.puts))
	}
}

func TestProcessOneSkipsRasterizedProduceForGap(t *testing.T) {
	transport := &fakeTransport{messages: []string{gapFixture()}}
	store := &fakeStore{}
	worker := New(transport, store, Config{
		OutputTopic: outputTopic, RasterizedTopic: rasterizedTopic, Bucket: "bucket", Renderer: &fakeRenderer{resp: rasterResponse()},
	})

	processed, err := worker.ProcessOne(context.Background())
	if err != nil || !processed {
		t.Fatalf("ProcessOne = %v, %v", processed, err)
	}
	if len(transport.produced) != 1 {
		t.Fatalf("produced %d records, want 1 (gap has no raster)", len(transport.produced))
	}
}

func TestProcessOneRasterizedProduceFailure(t *testing.T) {
	transport := &fakeTransport{messages: []string{geometryEventFixture}, produceErr: context.DeadlineExceeded, failTopic: "rg.glyph-rasterized.v1"}
	store := &fakeStore{}
	worker := New(transport, store, Config{
		OutputTopic: outputTopic, RasterizedTopic: rasterizedTopic, Bucket: "bucket", Renderer: &fakeRenderer{resp: rasterResponse()},
	})

	if _, err := worker.ProcessOne(context.Background()); err == nil {
		t.Fatal("ProcessOne succeeded despite rasterized produce failure")
	}
	if len(transport.produced) != 1 {
		t.Fatalf("produced %d records, want 1 (normalized only)", len(transport.produced))
	}
}

func TestPartitionKeyHandlesMalformedEvent(t *testing.T) {
	if got := partitionKey("not json"); got != "" {
		t.Fatalf("partitionKey = %q, want empty", got)
	}
	if got := partitionKey(`{"data":"not an object"}`); got != "" {
		t.Fatalf("partitionKey = %q, want empty", got)
	}
}
