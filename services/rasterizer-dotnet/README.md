# rasterizer-dotnet

C#/.NET gRPC rasterizer (Milestone 6, Stage 4 of the architecture).
Implements `rg.rasterizer.v1.Rasterizer.RenderGlyph`: normalized em-square
segments are drawn onto a transparent canvas with rounded caps, configurable
antialiasing and stroke width, deterministic integer supersampling with box
downsampling, cropped to the drawn content plus an OCR margin, and encoded
as PNG. The PNG bytes are stored in MinIO under a deterministic object key
that embeds the section 13.5 operation ID, so duplicate requests are
idempotent (same key, byte-identical artifact).

Rendering uses **ImageSharp** (`SixLabors.ImageSharp` + `.Drawing`), the
local rendering library chosen in ADR-0008 ("SkiaSharp or an equivalent
local rendering library" per architecture Stage 4). The service receives
only geometric segments and opaque identifiers — never the phrase, the
expected character, or a code point.

## Request contract

`RenderGlyphRequest` (see `contracts/proto/rasterizer/v1/rasterizer.proto`):

- `canvas` — target size (512×512 for the vector-normalizer default) and
  baseline; the 1024-unit em-square is mapped onto it uniformly.
- `profile` — `stroke_width` in em units, `antialias`, `line_cap`
  (`round`/`butt`/`square`), `supersampling` (1/2/4).
- `segments` — normalized line segments; every coordinate must be finite.
- `input_artifact_sha256` — SHA-256 of the input normalized artifact; the
  idempotency input hash for the operation ID.

Validation at the trust boundary rejects (gRPC `InvalidArgument`):
non-finite coordinates, empty or oversized segment lists
(`RASTERIZER_MAX_SEGMENTS`, default 8192), canvases outside
`RASTERIZER_MAX_CANVAS` (default 2048), unknown line caps, unsupported
supersampling factors, and malformed input hashes.

## Response

`RenderGlyphResponse` carries `artifact_id` (stable RFC 4122 UUID derived
from the operation ID), `object_key`, `sha256`, `width`, `height`,
`byte_count`, and `content_type` (`image/png`). The event published by the
Go normalizer copies these fields into `raster` (maturity 30 -> 40).

## Commands

```bash
dotnet build --nologo            # build
dotnet test --nologo             # unit tests (xUnit)
dotnet format whitespace         # format
dotnet format --verify-no-changes  # format check
dotnet run --project cli -- version   # banner
RASTERIZER_PORT=50051 dotnet run --project cli -- serve   # gRPC server
```

`serve` reads `RASTERIZER_PORT` (default 50051), `RASTERIZER_STORE`
(`s3` default | `local` for the host integration harness),
`RASTERIZER_BUCKET`, `RASTERIZER_LOCAL_DIR`, `RASTERIZER_MAX_SEGMENTS`,
`RASTERIZER_MAX_CANVAS`, and `MINIO_ENDPOINT` (must include the scheme) /
`MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY`.

The endpoint is HTTP/2-only (cleartext h2c): with `Http1AndHttp2` Kestrel
falls back to HTTP/1 when TLS is absent (see ADR-0008).

## Coverage

```bash
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:Threshold=90
```

Generated gRPC/message code under `generated/` is excluded from the coverage
gate (`ExcludeByFile` in the test project) and from `dotnet format`
(`generated_code = true` in `generated/.editorconfig`). Regenerate it with
`scripts/gen-csharp-proto.sh` (pinned SDK container on arm64 macOS, native
on x86_64 Linux); never hand-edit generated code.

## Dependencies

Pinned in `packages.lock.json` (restore is lock-file verified): Grpc.AspNetCore
2.83.0, Grpc.Tools 2.83.0, Google.Protobuf 3.35.1, Minio 7.0.0,
SixLabors.ImageSharp 3.1.12, SixLabors.ImageSharp.Drawing 2.1.7. Container
base images are tag-pinned: `mcr.microsoft.com/dotnet/sdk:10.0.302` builder,
`mcr.microsoft.com/dotnet/aspnet:10.0.9` runtime. The SDK version is pinned
in `versions.env` (`DOTNET_SDK_VERSION`).
