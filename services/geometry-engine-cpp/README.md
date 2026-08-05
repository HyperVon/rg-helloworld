# geometry-engine-cpp

C++20 geometry expansion service (Milestone 5). Consumes
`rg.glyph-blueprints.v1` CloudEvents, expands POLYLINE/POINT/ARC primitives
into explicit line segments (finite-coordinate validation, zero-length
removal, exactly-collinear merging, configurable arc subdivisions), computes
bounding box / total length / intersection count / deterministic SHA-256, and
publishes `GeometryExpanded` events to `rg.geometry-expanded.v1`.

Blueprint and geometry artifacts are stored in MinIO under deterministic
object keys embedding the operation ID
(`runs/{runId}/geometry-attempt-{attempt}-{operationId}.json`,
`runs/{runId}/blueprint.json`; see ADR-0007). Gap blueprints produce
`GAP_GEOMETRY` layout records (advance width, left/right bearing) instead of
being skipped. Envelope `id` is a UUID derived from the operation ID;
`time`/`causationid` are inherited from the input event for byte-determinism.

## Modes

```bash
geometry_engine --version                          # version banner
geometry_engine --once < event.json                # one-shot: stdin CloudEvent -> stdout event
geometry_engine --once --artifacts-dir DIR < ...   # also write blueprint + geometry artifacts locally
```

Worker mode reads environment variables: `KAFKA_BOOTSTRAP`, `KAFKA_GROUP_ID`,
`GEOMETRY_INPUT_TOPIC`, `GEOMETRY_OUTPUT_TOPIC`, `GEOMETRY_ARC_SUBDIVISIONS`,
and `MINIO_ENDPOINT` / `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` /
`MINIO_BUCKET` (or `MINIO_USE_SSL`).

## Commands

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release   # configure
cmake --build build                              # build
ctest --test-dir build --output-on-failure       # tests
clang-format -i src/*.cpp include/geometry_engine/*.hpp tests/*.cpp
```

## Dependencies

- librdkafka (pinned in `versions.env`: `LIBRDKAFKA_VERSION` for macOS Homebrew,
  `LIBRDKAFKA_DEBIAN_VERSION` for the Debian-bookworm Docker image,
  `LIBRDKAFKA_UBUNTU_VERSION` for CI Ubuntu).
- S3 uploads use a minimal AWS SigV4 + POSIX-socket HTTP client (no libcurl).

## Coverage

CI builds with `-DENABLE_COVERAGE=ON` and enforces a 90% line-coverage
threshold via gcovr (the librdkafka client glue in `src/kafka.cpp` is
excluded). The `banner` CTest case executes the real binary so `main()` is
covered.
