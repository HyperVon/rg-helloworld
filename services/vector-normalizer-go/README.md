# vector-normalizer-go

Go vector normalization service (Milestone 5). Consumes
`rg.geometry-expanded.v1` CloudEvents (franz-go), normalizes each glyph's
geometry into a standard em-square: positive canvas space, aspect-preserving
scale, common baseline alignment, side bearings, fixed-precision
quantization. Produces deterministic polyline-only SVG (no text elements)
with a SHA-256, stores normalized JSON geometry + SVG + layout metadata in
MinIO (minio-go), and publishes `VectorNormalized` events to
`rg.glyph-normalized.v1` (see ADR-0007).

Gap geometry normalizes into layout metadata (advance width, bearings) with
no rasterizer involvement. Artifact keys are deterministic:
`runs/{runId}/glyphs/{position}-{glyphInstanceId}/normalized-attempt-1-{hash}.json|.svg`.
Envelope `id` is derived from the operation ID; `time`/`causationid` are
inherited from the input event for byte-determinism.

## Modes

```bash
vector-normalizer --version                              # version banner
vector-normalizer --once < event.json > event-out.json   # one-shot: stdin CloudEvent -> stdout event
vector-normalizer --once --emit-artifacts-to DIR < ...   # also write normalized artifacts locally
```

Worker mode reads environment variables: `KAFKA_BOOTSTRAP`, `KAFKA_GROUP_ID`,
`GEOMETRY_INPUT_TOPIC`, `NORMALIZED_OUTPUT_TOPIC`, and `MINIO_ENDPOINT` /
`MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` / `MINIO_BUCKET` / `MINIO_USE_SSL`.

## Commands

```bash
go build ./...      # compile
go test ./...       # unit tests
go vet ./...        # static analysis
gofmt -l .          # format check
```

## Dependencies

- franz-go (pinned: `github.com/twmb/franz-go` v1.21.5, `kadm` v1.18.0,
  `kfake` pseudo-version in `go.mod`) and `github.com/minio/minio-go/v7`
  v7.2.1.

## Coverage

CI enforces a 90% line-coverage threshold via `go test -cover`.
