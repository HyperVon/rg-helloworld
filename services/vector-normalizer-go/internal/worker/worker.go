// Package worker implements the vector-normalizer pipeline: consume a
// GeometryExpanded event, normalize the geometry, store the normalized JSON
// and SVG artifacts, and publish the VectorNormalized event.
package worker

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"rghello.dev/vector-normalizer/internal/geom"
	"rghello.dev/vector-normalizer/internal/kafka"
	"rghello.dev/vector-normalizer/internal/s3store"
	"rghello.dev/vector-normalizer/internal/svg"
)

const (
	stepName        = "normalize-vector"
	stepVersion     = "1.0.0"
	outputTopic     = "rg.glyph-normalized.v1"
	source          = "vector-normalizer"
	contentTypeJSON = "application/json"
	contentTypeSVG  = "image/svg+xml"
)

// Config holds the runtime knobs for the pipeline.
type Config struct {
	OutputTopic string
	Bucket      string
}

// Outcome is the result of processing one geometry event.
type Outcome struct {
	OutputEvent    string
	NormalizedKey  string
	NormalizedJSON string
	SvgKey         string
	SvgContent     string
}

type cloudEvent struct {
	SpecVersion     string          `json:"specversion"`
	ID              string          `json:"id"`
	Source          string          `json:"source"`
	Type            string          `json:"type"`
	Subject         string          `json:"subject"`
	Time            string          `json:"time"`
	DataContentType string          `json:"datacontenttype"`
	CorrelationID   string          `json:"correlationid"`
	CausationID     string          `json:"causationid"`
	Data            json.RawMessage `json:"data"`
}

type geometryData struct {
	RunID           string   `json:"runId"`
	StepID          string   `json:"stepId"`
	GlyphInstanceID string   `json:"glyphInstanceId"`
	Position        int      `json:"position"`
	Attempt         int      `json:"attempt"`
	InputArtifacts  []string `json:"inputArtifacts"`
	Geometry        struct {
		Kind           string         `json:"kind"`
		Segments       []geom.Segment `json:"segments"`
		AdvanceWidth   float64        `json:"advanceWidth"`
		GeometrySha256 string         `json:"geometrySha256"`
	} `json:"geometry"`
}

// Process transforms one geometry CloudEvent into the normalized artifacts
// and the VectorNormalized CloudEvent. Deterministic for a given input.
func Process(inputEvent string, cfg Config) (Outcome, error) {
	if cfg.OutputTopic == "" {
		cfg.OutputTopic = outputTopic
	}
	if cfg.Bucket == "" {
		return Outcome{}, fmt.Errorf("worker: bucket is required")
	}
	var envelope cloudEvent
	if err := json.Unmarshal([]byte(inputEvent), &envelope); err != nil {
		return Outcome{}, fmt.Errorf("worker: parse event: %w", err)
	}
	var data geometryData
	if err := json.Unmarshal(envelope.Data, &data); err != nil {
		return Outcome{}, fmt.Errorf("worker: parse data: %w", err)
	}
	if data.GlyphInstanceID == "" {
		return Outcome{}, fmt.Errorf("worker: data has no glyphInstanceId")
	}

	operationID := operationID(data)
	directory := fmt.Sprintf("runs/%s/glyphs/%d-%s", data.RunID, data.Position, data.GlyphInstanceID)
	outcome := Outcome{}
	outcome.NormalizedKey = fmt.Sprintf("%s/normalized-attempt-%d-%s.json", directory, data.Attempt, operationID)
	outcome.SvgKey = fmt.Sprintf("%s/normalized-attempt-%d-%s.svg", directory, data.Attempt, operationID)

	normalized := geom.Normalize(geom.GeometryPayload{
		Kind:           data.Geometry.Kind,
		Segments:       data.Geometry.Segments,
		AdvanceWidth:   data.Geometry.AdvanceWidth,
		GeometrySha256: data.Geometry.GeometrySha256,
	})
	normalizedJSON, err := normalizedArtifact(data, normalized)
	if err != nil {
		return Outcome{}, err
	}
	outcome.NormalizedJSON = normalizedJSON
	outcome.SvgContent = svg.Build(normalized.Segments)

	eventJSON, err := normalizedEvent(envelope, data, normalized, outcome, operationID)
	if err != nil {
		return Outcome{}, err
	}
	outcome.OutputEvent = eventJSON
	return outcome, nil
}

// operationID is the deterministic idempotency key (architecture section
// 13.5): SHA-256 over run, step, glyph, attempt, and the input artifact hash.
func operationID(data geometryData) string {
	hash := sha256.Sum256([]byte(data.RunID + stepName + data.GlyphInstanceID +
		strconv.Itoa(data.Attempt) + data.Geometry.GeometrySha256))
	return hex.EncodeToString(hash[:])
}

// uuidFromOperationID derives a stable RFC 4122 version-4 UUID from the
// first 16 bytes of the operation ID so the event id is deterministic.
func uuidFromOperationID(operationID string) string {
	bytes := make([]byte, 16)
	for i := 0; i < 16; i++ {
		bytes[i] = hexVal(operationID[2*i])<<4 | hexVal(operationID[2*i+1])
	}
	bytes[6] = bytes[6]&0x0F | 0x40
	bytes[8] = bytes[8]&0x3F | 0x80
	return fmt.Sprintf("%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
		bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
		bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
}

func hexVal(c byte) byte {
	switch {
	case c >= '0' && c <= '9':
		return c - '0'
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10
	default:
		return c - 'A' + 10
	}
}

func normalizedArtifact(data geometryData, normalized geom.Normalized) (string, error) {
	artifact := map[string]any{
		"runId":               data.RunID,
		"stepId":              data.StepID,
		"glyphInstanceId":     data.GlyphInstanceID,
		"position":            data.Position,
		"attempt":             data.Attempt,
		"kind":                data.Geometry.Kind,
		"advanceWidth":        data.Geometry.AdvanceWidth,
		"leftBearing":         geom.LeftBearing,
		"rightBearing":        geom.RightBearing,
		"inputGeometrySha256": data.Geometry.GeometrySha256,
		"normalizedGeometry": map[string]any{
			"segments": normalized.Segments,
			"viewBox": map[string]any{
				"width":  normalized.ViewBox.Width,
				"height": normalized.ViewBox.Height,
			},
			"baseline": normalized.Baseline,
		},
	}
	body, err := json.Marshal(artifact)
	if err != nil {
		return "", fmt.Errorf("worker: marshal normalized artifact: %w", err)
	}
	return string(body), nil
}

func normalizedEvent(envelope cloudEvent, data geometryData, normalized geom.Normalized,
	outcome Outcome, operationID string) (string, error) {
	event := map[string]any{
		"specversion":     "1.0",
		"id":              uuidFromOperationID(operationID),
		"source":          source,
		"type":            outputTopic,
		"subject":         fmt.Sprintf("runs/%s/glyphs/%s", data.RunID, data.GlyphInstanceID),
		"datacontenttype": "application/json",
		"correlationid":   data.RunID,
	}
	if envelope.Time != "" {
		event["time"] = envelope.Time
	}
	if envelope.ID != "" {
		event["causationid"] = envelope.ID
	}
	inputArtifacts := data.InputArtifacts
	if len(inputArtifacts) == 0 {
		inputArtifacts = []string{}
	}
	event["data"] = map[string]any{
		"runId":           data.RunID,
		"stepId":          data.StepID,
		"glyphInstanceId": data.GlyphInstanceID,
		"position":        data.Position,
		"attempt":         data.Attempt,
		"inputMaturity":   20,
		"outputMaturity":  30,
		"inputArtifacts":  inputArtifacts,
		"outputArtifacts": []string{outcome.NormalizedKey, outcome.SvgKey},
		"transformation": map[string]any{
			"name":    stepName,
			"version": stepVersion,
		},
		"normalizedGeometry": map[string]any{
			"segments": normalized.Segments,
			"viewBox": map[string]any{
				"width":  normalized.ViewBox.Width,
				"height": normalized.ViewBox.Height,
			},
			"baseline": normalized.Baseline,
		},
		"svgSha256": svg.Sha256Hex(outcome.SvgContent),
	}
	body, err := json.Marshal(event)
	if err != nil {
		return "", fmt.Errorf("worker: marshal normalized event: %w", err)
	}
	return string(body), nil
}

// Worker runs the consume-store-publish loop.
type Worker struct {
	transport kafka.Transport
	store     s3store.Store
	config    Config
}

// New wires a worker to its transport, store, and configuration.
func New(transport kafka.Transport, store s3store.Store, config Config) *Worker {
	return &Worker{transport: transport, store: store, config: config}
}

// ProcessOne polls one event, processes it, stores both artifacts, and
// publishes the result. Returns false when the poll produced no message.
func (w *Worker) ProcessOne(ctx context.Context) (bool, error) {
	message, ok := w.transport.Poll(ctx)
	if !ok {
		return false, nil
	}
	outcome, err := Process(message, w.config)
	if err != nil {
		return true, err
	}
	if err := w.store.PutObject(ctx, w.config.Bucket, outcome.NormalizedKey,
		[]byte(outcome.NormalizedJSON), contentTypeJSON); err != nil {
		return true, err
	}
	if err := w.store.PutObject(ctx, w.config.Bucket, outcome.SvgKey,
		[]byte(outcome.SvgContent), contentTypeSVG); err != nil {
		return true, err
	}
	if err := w.transport.Produce(ctx, w.config.OutputTopic, partitionKey(outcome.OutputEvent),
		outcome.OutputEvent); err != nil {
		return true, err
	}
	return true, nil
}

func partitionKey(outputEvent string) string {
	var envelope cloudEvent
	if err := json.Unmarshal([]byte(outputEvent), &envelope); err != nil {
		return ""
	}
	var data geometryData
	if err := json.Unmarshal(envelope.Data, &data); err != nil {
		return ""
	}
	return data.RunID + ":" + data.GlyphInstanceID
}

// Reject prohibited fields: the section 7.3 names must never appear in a
// downstream event. This guard runs on every produced event in tests.
var ProhibitedFields = []string{"message", "targetText", "expectedCharacter",
	"unicodeCodePoint", "characterName", "glyphLabel"}

// ContainsProhibitedField reports whether raw JSON contains any of the
// prohibited downstream field names.
func ContainsProhibitedField(raw string) bool {
	for _, field := range ProhibitedFields {
		if strings.Contains(raw, `"`+field+`"`) {
			return true
		}
	}
	return false
}
