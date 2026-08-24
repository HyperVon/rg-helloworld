# ADR-0009: Milestone 7 - Python Image Pipeline Composition and Preprocessing

## Status

Accepted (Milestone 0.1.0-milestone7)

## Context

The pipeline requires two run-level fan-in transformations:

1. **Phrase composition** (Stage 5, maturity 40 → 50): Combine individual
   rasterized glyph PNGs and gap layout records into a single phrase image.
2. **OCR preprocessing** (Stage 6, maturity 50 → 60): Transform the raw phrase
   image into an OCR-ready image with position crops.

Both stages are owned by the Python image pipeline service and must be
deterministic, idempotent, and must not receive the expected plaintext.

## Decision

### Libraries

Use **Pillow** for all image I/O and compositing operations. Pillow provides:

- Deterministic PNG encoding with explicit compression settings.
- RGBA-aware compositing with transparency support.
- Image resizing with explicit resampling filters.

Use **numpy** for array-based connected-component analysis in noise removal.

Do **not** use OpenCV for this milestone. OpenCV adds significant binary
weight and complexity; Pillow's autocontrast and point operations are
sufficient for the preprocessing requirements.

### Composition Approach

1. Sort incoming glyph inputs by position.
2. Align each glyph to the baseline using the stored baseline metadata.
3. Apply advance widths to determine horizontal layout.
4. Insert gap widths from gap layout records (no rasterization needed).
5. Add phrase-level margins.
6. Create a single RGBA canvas with transparent background.
7. Paste each glyph with its alpha channel as the mask.
8. Generate a composition manifest mapping each position to a pixel bounding
   box.

### Preprocessing Approach

1. Convert the composed phrase image to grayscale.
2. Apply contrast enhancement using `ImageOps.autocontrast`.
3. Apply a deterministic binary threshold via a lookup table.
4. Remove isolated noise pixels using connected-component analysis on the
   binary image; discard components smaller than a configurable threshold.
5. Add a clean white border using `ImageOps.expand`.
6. Optionally scale by an integer factor using nearest-neighbor resampling.
7. Crop each position from the preprocessed image using the composition
   manifest bounding boxes.
8. Generate a preprocessing report with threshold, scale, foreground ratio,
   and connected-component count.

### Determinism

All operations use fixed parameters. No random seeds or time-dependent
values are used in image generation. PNG encoding uses `optimize=True` and a
fixed `zlib_level`.

### Event Publishing

Composition and preprocessing each publish a single run-level event:

- `rg.phrase-composed.v1` (maturity 40 → 50)
- `rg.ocr-images.v1` (maturity 50 → 60)

Event IDs are derived from a deterministic operation ID:
`SHA256(runId + stepName + attempt + inputArtifactHash)`.

## Consequences

- Pillow and numpy become pinned dependencies in `versions.env` and
  `requirements-dev.txt`.
- The service requires `--once` modes for integration testing without Kafka
  or MinIO.
- Full Kafka consumer logic is deferred but the core transformation logic is
  complete and testable.
- The Dockerfile uses a `-slim` Python base image (`3.14.6-slim` since the
  milestone-11 toolchain standardization) to avoid the
  full Python image weight while providing system libraries needed by
  Pillow's C extensions.
