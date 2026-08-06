# vector-normalizer-go

Go vector normalization + rasterization dispatch service (Milestone 6).
Consumes `rg.geometry-expanded.v1` CloudEvents (franz-go), normalizes each
glyph's geometry into a standard em-square: positive canvas space,
aspect-preserving scale, common baseline alignment, side bearings,
fixed-precision quantization. Produces deterministic polyline-only SVG (no
text elements) with a SHA-256, stores normalized JSON geometry + SVG + layout
metadata in MinIO (minio-go), and publishes `VectorNormalized` events to
`rg.glyph-normalized.v1` (see ADR-0007).

For drawable glyphs the normalized segments are then rasterized over gRPC
(`rg.rasterizer.v1.Rasterizer.RenderGlyph`, see `internal/rasterproto` and
`internal/rasterclient`): a 512×512 canvas at baseline 400 px with the
default render profile (28-unit round-cap stroke, antialiased, 2×
supersampling). The client enforces a ten-second per-call deadline and
retries transient status codes only (`Unavailable`, `ResourceExhausted`,
`Aborted`). The resulting PNG object key and metadata are published as
`GlyphRasterized` events to `rg.glyph-rasterized.v1` (maturity 30 -> 40,
`transformation.name` = `rasterize-glyph`, section 13.5 operation ID —
identical to the one the C# service embeds in the artifact key).

Gap geometry normalizes into layout metadata (advance width, bearings) with
no rasterizer involvement and no rasterized event. Artifact keys are
deterministic:
`runs/{runId}/glyphs/{position}-{glyphInstanceId}/normalized-attempt-1-{hash}.json|.svg`.
Envelope `id` is derived from the operation ID; `time`/`causationid` are
inherited from the input event for byte-determinism.

## Modes

```bash
vector-normalizer version                                  # version banner
vector-normalizer --once < event.json > event-out.json     # one-shot: stdin CloudEvent -> stdout event(s)
vector-normalizer --once --emit-artifacts-to DIR < ...     # also write normalized artifacts locally
vector-normalizer --once --rasterizer-url HOST:PORT < ...  # also rasterize drawables; rasterized event on stdout
```

Worker mode reads environment variables: `KAFKA_BOOTSTRAP`, `KAFKA_GROUP_ID`,
`GEOMETRY_INPUT_TOPIC`, `NORMALIZED_OUTPUT_TOPIC`,
`NORMALIZER_RASTERIZED_TOPIC` (default `rg.glyph-rasterized.v1`),
`RASTERIZER_ADDR` (rasterizer gRPC address; when set, drawable glyphs are
rasterized before the rasterized event is published), and `MINIO_ENDPOINT` /
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
  `kfake` pseudo-version in `go.mod`), `github.com/minio/minio-go/v7`
  v7.2.1, `google.golang.org/grpc` v1.83.0, and
  `google.golang.org/protobuf` v1.36.11.
- The gRPC client code under `internal/rasterproto/` is generated from the
  proto contract by `scripts/gen-proto.sh` (pinned protoc 35.1 +
  protoc-gen-go v1.36.11 + protoc-gen-go-grpc v1.6.2); `make contracts` runs
  it and CI verifies no drift (`proto-gen-check`). Generated code is never
  hand-edited and is excluded from the coverage profile.

## Coverage

CI enforces a 90% line-coverage threshold via `go test -cover` (the
generated `internal/rasterproto` package is excluded, mirroring the C++
gcovr excludes).
