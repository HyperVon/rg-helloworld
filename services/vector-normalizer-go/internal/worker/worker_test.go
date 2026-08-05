package worker

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

const geometryEventFixture = `{
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

func mustProcess(t *testing.T, input string) Outcome {
	t.Helper()
	outcome, err := Process(input, Config{Bucket: "rube-goldberg-artifacts"})
	if err != nil {
		t.Fatalf("Process: %v", err)
	}
	return outcome
}

func TestProcessDrawable(t *testing.T) {
	outcome := mustProcess(t, geometryEventFixture)

	var event map[string]any
	if err := json.Unmarshal([]byte(outcome.OutputEvent), &event); err != nil {
		t.Fatalf("output event not JSON: %v", err)
	}
	if event["specversion"] != "1.0" || event["source"] != "vector-normalizer" {
		t.Fatalf("envelope wrong: %v", event)
	}
	if event["type"] != "rg.glyph-normalized.v1" {
		t.Fatalf("type = %v", event["type"])
	}
	if event["time"] != "2026-08-05T00:00:00.000Z" {
		t.Fatalf("time not inherited: %v", event["time"])
	}
	if event["causationid"] != "11111111-1111-4111-8111-111111111111" {
		t.Fatalf("causationid = %v", event["causationid"])
	}
	if event["correlationid"] != "22222222-2222-4222-8222-222222222222" {
		t.Fatalf("correlationid = %v", event["correlationid"])
	}
	id, ok := event["id"].(string)
	if !ok || len(id) != 36 {
		t.Fatalf("id = %v, want 36-char UUID", event["id"])
	}
	if ContainsProhibitedField(outcome.OutputEvent) {
		t.Fatalf("output event contains prohibited fields: %s", outcome.OutputEvent)
	}

	data := event["data"].(map[string]any)
	if data["inputMaturity"].(float64) != 20 || data["outputMaturity"].(float64) != 30 {
		t.Fatalf("maturity = %v -> %v, want 20 -> 30", data["inputMaturity"], data["outputMaturity"])
	}
	transformation := data["transformation"].(map[string]any)
	if transformation["name"] != "normalize-vector" {
		t.Fatalf("transformation = %v", transformation)
	}
	normalized := data["normalizedGeometry"].(map[string]any)
	segments := normalized["segments"].([]any)
	if len(segments) != 3 {
		t.Fatalf("normalized segments = %d, want 3", len(segments))
	}
	viewBox := normalized["viewBox"].(map[string]any)
	if viewBox["width"].(float64) != 1024 || viewBox["height"].(float64) != 1024 {
		t.Fatalf("viewBox = %v", viewBox)
	}
	if normalized["baseline"].(float64) != 800 {
		t.Fatalf("baseline = %v", normalized["baseline"])
	}
	svgHash, _ := data["svgSha256"].(string)
	if svgHash == "" {
		t.Fatal("missing svgSha256")
	}

	// The artifact keys are deterministic and referenceable.
	inputArtifacts := data["inputArtifacts"].([]any)
	if len(inputArtifacts) != 1 {
		t.Fatalf("inputArtifacts = %v", inputArtifacts)
	}
	outputArtifacts := data["outputArtifacts"].([]any)
	if len(outputArtifacts) != 2 {
		t.Fatalf("outputArtifacts = %v", outputArtifacts)
	}
	if !strings.HasPrefix(outcome.NormalizedKey,
		"runs/22222222-2222-4222-8222-222222222222/glyphs/0-55555555-5555-4555-8555-555555555555/normalized-attempt-1-") {
		t.Fatalf("normalized key = %q", outcome.NormalizedKey)
	}
	if !strings.HasSuffix(outcome.NormalizedKey, ".json") || !strings.HasSuffix(outcome.SvgKey, ".svg") {
		t.Fatalf("artifact extensions wrong: %q %q", outcome.NormalizedKey, outcome.SvgKey)
	}
	if outputArtifacts[0] != outcome.NormalizedKey || outputArtifacts[1] != outcome.SvgKey {
		t.Fatalf("outputArtifacts do not match keys")
	}

	// The normalized artifact records layout metadata.
	var artifact map[string]any
	if err := json.Unmarshal([]byte(outcome.NormalizedJSON), &artifact); err != nil {
		t.Fatalf("normalized artifact not JSON: %v", err)
	}
	if artifact["kind"] != "DRAWABLE_GEOMETRY" || artifact["advanceWidth"].(float64) != 1.0 {
		t.Fatalf("artifact metadata wrong: %v", artifact)
	}
	if artifact["inputGeometrySha256"] != "28f75f5ee107f08144aa9a9ac1eb56c82c58336d4d99f7dab3da91b009d43636" {
		t.Fatalf("input hash not recorded: %v", artifact["inputGeometrySha256"])
	}
	if strings.Contains(outcome.SvgContent, "<text") {
		t.Fatalf("SVG contains text elements: %s", outcome.SvgContent)
	}
}

func TestProcessGap(t *testing.T) {
	var input map[string]any
	if err := json.Unmarshal([]byte(geometryEventFixture), &input); err != nil {
		t.Fatalf("fixture parse: %v", err)
	}
	data := input["data"].(map[string]any)
	geometry := data["geometry"].(map[string]any)
	geometry["kind"] = "GAP_GEOMETRY"
	geometry["segments"] = []any{}
	raw, err := json.Marshal(input)
	if err != nil {
		t.Fatalf("fixture marshal: %v", err)
	}

	outcome := mustProcess(t, string(raw))
	var event map[string]any
	_ = json.Unmarshal([]byte(outcome.OutputEvent), &event)
	eventData := event["data"].(map[string]any)
	normalized := eventData["normalizedGeometry"].(map[string]any)
	if len(normalized["segments"].([]any)) != 0 {
		t.Fatalf("gap normalized segments = %v, want empty", normalized["segments"])
	}
	if strings.Contains(outcome.SvgContent, "<polyline") {
		t.Fatalf("gap SVG must not draw: %s", outcome.SvgContent)
	}
	var artifact map[string]any
	if err := json.Unmarshal([]byte(outcome.NormalizedJSON), &artifact); err != nil {
		t.Fatalf("gap artifact not JSON: %v", err)
	}
	if artifact["kind"] != "GAP_GEOMETRY" {
		t.Fatalf("gap artifact kind = %v", artifact["kind"])
	}
	if artifact["advanceWidth"].(float64) != 1.0 {
		t.Fatalf("gap advanceWidth = %v", artifact["advanceWidth"])
	}
}

func TestProcessDeterministic(t *testing.T) {
	first := mustProcess(t, geometryEventFixture)
	second := mustProcess(t, geometryEventFixture)
	if first.OutputEvent != second.OutputEvent {
		t.Fatal("output event not deterministic")
	}
	if first.NormalizedJSON != second.NormalizedJSON {
		t.Fatal("normalized artifact not deterministic")
	}
	if first.SvgContent != second.SvgContent {
		t.Fatal("SVG not deterministic")
	}
	if first.NormalizedKey != second.NormalizedKey {
		t.Fatal("artifact keys not deterministic")
	}
}

func TestProcessRejectsInvalidInput(t *testing.T) {
	cases := []string{
		"not json",
		`{"specversion":"1.0","data":{}}`,
		`{"specversion":"1.0","data":{"glyphInstanceId":""}}`,
	}
	for _, input := range cases {
		if _, err := Process(input, Config{Bucket: "bucket"}); err == nil {
			t.Fatalf("Process(%q) succeeded, want error", input)
		}
	}
	if _, err := Process(geometryEventFixture, Config{}); err == nil {
		t.Fatal("Process without bucket succeeded, want error")
	}
}

type fakeTransport struct {
	messages    []string
	pollIndex   int
	produced    []string
	produceErr  error
	commitCalls int
}

func (f *fakeTransport) Poll(context.Context) (string, bool) {
	if f.pollIndex >= len(f.messages) {
		return "", false
	}
	message := f.messages[f.pollIndex]
	f.pollIndex++
	return message, true
}

func (f *fakeTransport) Produce(_ context.Context, topic, key, value string) error {
	if f.produceErr != nil {
		return f.produceErr
	}
	f.produced = append(f.produced, topic+"|"+key+"|"+value)
	return nil
}

func (f *fakeTransport) Commit(context.Context) error {
	f.commitCalls++
	return nil
}

func (f *fakeTransport) Close() {}

type fakeStore struct {
	puts      []string
	putErr    error
	failAfter int
}

func (f *fakeStore) PutObject(_ context.Context, bucket, key string, body []byte, contentType string) error {
	if f.putErr != nil {
		return f.putErr
	}
	if f.failAfter > 0 && len(f.puts) >= f.failAfter {
		return context.DeadlineExceeded
	}
	f.puts = append(f.puts, bucket+"/"+key+"|"+string(body)+"|"+contentType)
	return nil
}

func TestWorkerProcessOne(t *testing.T) {
	transport := &fakeTransport{messages: []string{geometryEventFixture}}
	store := &fakeStore{}
	loop := New(transport, store, Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "rube-goldberg-artifacts"})

	processed, err := loop.ProcessOne(context.Background())
	if err != nil {
		t.Fatalf("ProcessOne: %v", err)
	}
	if !processed {
		t.Fatal("ProcessOne returned not processed")
	}
	if len(store.puts) != 2 {
		t.Fatalf("puts = %d, want 2", len(store.puts))
	}
	if !strings.HasPrefix(store.puts[0], "rube-goldberg-artifacts/runs/22222222-2222-4222-8222-222222222222/glyphs/0-") {
		t.Fatalf("first put = %q", store.puts[0])
	}
	if !strings.Contains(store.puts[0], ".json|") {
		t.Fatalf("first put target = %q", store.puts[0])
	}
	if !strings.HasSuffix(store.puts[1], "|image/svg+xml") {
		t.Fatalf("second put target = %q", store.puts[1])
	}
	if len(transport.produced) != 1 {
		t.Fatalf("produced = %d, want 1", len(transport.produced))
	}
	if !strings.HasPrefix(transport.produced[0], "rg.glyph-normalized.v1|22222222-2222-4222-8222-222222222222:55555555-5555-4555-8555-555555555555|") {
		t.Fatalf("produce metadata wrong: %q", transport.produced[0])
	}

	// No more messages: poll timeout path.
	processed, err = loop.ProcessOne(context.Background())
	if err != nil || processed {
		t.Fatalf("second ProcessOne = %v %v, want false nil", processed, err)
	}
}

func TestWorkerStoreFailure(t *testing.T) {
	transport := &fakeTransport{messages: []string{geometryEventFixture}}
	store := &fakeStore{putErr: context.DeadlineExceeded}
	loop := New(transport, store, Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"})
	if _, err := loop.ProcessOne(context.Background()); err == nil {
		t.Fatal("ProcessOne with failing store succeeded")
	}
}

func TestWorkerProduceFailure(t *testing.T) {
	transport := &fakeTransport{messages: []string{geometryEventFixture}, produceErr: context.DeadlineExceeded}
	store := &fakeStore{}
	loop := New(transport, store, Config{OutputTopic: "rg.glyph-normalized.v1", Bucket: "bucket"})
	if _, err := loop.ProcessOne(context.Background()); err == nil {
		t.Fatal("ProcessOne with failing produce succeeded")
	}
}

func TestProcessWithoutEnvelopeExtras(t *testing.T) {
	// An event without time/id (e.g. produced by a minimal producer) must
	// still produce a valid event: time and causationid are omitted.
	input := `{"specversion":"1.0","datacontenttype":"application/json","data":{"runId":"22222222-2222-4222-8222-222222222222","stepId":"44444444-4444-4444-8444-444444444444","glyphInstanceId":"55555555-5555-4555-8555-555555555555","position":3,"attempt":1,"inputArtifacts":[],"outputArtifacts":[],"geometry":{"kind":"DRAWABLE_GEOMETRY","segments":[{"x1":0.0,"y1":0.0,"x2":1.0,"y2":0.0}],"advanceWidth":1.0,"totalLength":1.0,"geometrySha256":"abc"}}}`
	outcome := mustProcess(t, input)
	var event map[string]any
	if err := json.Unmarshal([]byte(outcome.OutputEvent), &event); err != nil {
		t.Fatalf("output not JSON: %v", err)
	}
	if _, has := event["time"]; has {
		t.Fatal("time must be omitted when the input has none")
	}
	if _, has := event["causationid"]; has {
		t.Fatal("causationid must be omitted when the input has no id")
	}
	if event["correlationid"] != "22222222-2222-4222-8222-222222222222" {
		t.Fatalf("correlationid = %v", event["correlationid"])
	}
}

func TestUuidFromOperationIDHandlesUppercase(t *testing.T) {
	upper := "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF"
	lower := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	if uuidFromOperationID(upper) != uuidFromOperationID(lower) {
		t.Fatal("uppercase hex must produce the same UUID as lowercase")
	}
}

func TestContainsProhibitedField(t *testing.T) {
	if ContainsProhibitedField(`{"expectedCharacter":"H"}`) != true {
		t.Fatal("expectedCharacter must be detected")
	}
	if ContainsProhibitedField(`{"x":1}`) {
		t.Fatal("clean payload flagged")
	}
}

func TestUuidFromOperationID(t *testing.T) {
	id := uuidFromOperationID("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
	if len(id) != 36 || id[14] != '4' {
		t.Fatalf("id = %q, want version-4 UUID shape", id)
	}
	if id != uuidFromOperationID("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") {
		t.Fatal("uuid derivation not deterministic")
	}
}
