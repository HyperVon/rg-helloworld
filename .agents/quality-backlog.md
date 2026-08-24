# Quality backlog

Durable store for findings from [continuous-quality](../.agents/skills/continuous-quality/SKILL.md)
and other QA work, so nothing survives only in chat. Add dated entries under
the section that matches their state. **L** items (integrity rules, secrets,
cluster/infrastructure, public contracts) should also become GitHub issues
with labels once confirmed.

## Open

<!-- new findings go here: - [S|M|L] YYYY-MM-DD: finding — path — evidence -->

### 2026-08-23 continuous-improvement cycle 1 (discovery: deps/integrity/hygiene/docs scouts, parent-validated)

Awaiting user decision (L / direction calls):

- [L] 2026-08-23: Phrase assembler has no Kafka dedupe; `enable.auto.commit=true` +
  `auto.offset.reset=earliest` means a redelivered `rg.symbols-adjudicated.v1`
  pushes a duplicate token, `assemble()` fails `DuplicatePosition`, and the whole
  run buffer is dropped (`"assembly failed, dropping run buffer"`). Integrity
  rule 9. — services/phrase-assembler-rust/src/main.rs:105-147,187
  → superseded by the [L] 2026-08-24 Done entry (register_token_step dedupe,
  composite step:attempt:position key).
- [L] 2026-08-23: image-pipeline publishes empty lineage on
  `rg.phrase-composed.v1` (`inputArtifacts: []`, consumes ~11 glyph events) and
  a synthetic `sha256 + "-manifest"` output descriptor. Integrity rule 8. —
  services/image-pipeline-python/src/rg_image_pipeline/worker.py:229-230
  → superseded by the [M] 2026-08-23 approved-batch Done entry (real lineage
  keys verified by integration gate).
- [L] 2026-08-23: image-pipeline `prepare-ocr-image` records its own OUTPUT hash
  as the sole input artifact; the real input was the phrase-composed objectKey,
  so the lineage chain breaks between maturity 50 and 60. Integrity rule 8. —
  services/image-pipeline-python/src/rg_image_pipeline/worker.py:317
  → superseded by the [M] 2026-08-23 approved-batch Done entry (same lineage
  fix; keys now real S3 paths).
- [L] 2026-08-23: image-pipeline buffers rasterized/geometry events per run with
  no dedupe before the >=11 flush heuristic; rebalance duplicates skew
  composition. Integrity rule 9. — worker.py:57,85
  → superseded by the [L] 2026-08-24 Done entry (accept_record dedupe,
  composite event_type:position:attempt:stepId key).
- [L] 2026-08-23: `rghw.sh --dry-run --quiet` literally echoes the acceptance
  phrase from script source (documented 12-byte behavior). Integrity rule 7
  letter vs launcher-preview behavior. — rghw.sh:146-150
  → superseded by the [M] 2026-08-23 approved-batch Done entry (literal
  removal verified at rghw.sh:150).
- [S] 2026-08-24 (from PR review T3): rghw.sh:205 keeps an inline
  `MINIO_MC_VERSION` default that duplicates the versions.env pin because
  rghw.sh does not source versions.env; a versions.env bump alone would leave
  local runs on the old mc tag. Deferred fix decision: source versions.env in
  rghw.sh or drop the duplicated default.
- [M] 2026-08-23: Weak-but-present lineage family (key-only inputArtifacts, no
  sha256 mapping) in vector-normalizer-go worker.go:225,349-362,
  geometry-engine-cpp service.cpp:122,174-176, adjudicator passthrough
  consumer.rb:56. Fix scope follows the image-pipeline lineage decision.
  → superseded by the [L] 2026-08-24 Done entry (chain-rule consistency fix).
- [S] 2026-08-24: ocr-worker-node consumer.ts (~line 165) echoes
  data.outputArtifacts from glyph-rasterized events into its own emitted event's
  outputArtifacts while also claiming its own observation keys — same
  double-claiming pattern fixed in adjudicator-ruby. Needs the chain-rule
  treatment: inputArtifacts = consumed event's outputArtifacts,
  outputArtifacts = keys this step wrote. Not in the approved batch; needs user
  approval before implementation.
- [M] 2026-08-23: Python toolchain split-brain: `.tool-versions`=3.14.6 +
  runbook says 3.14.6 + ruff `target-version="py314"` + status table says
  "Python 3.14+", while `versions.env PYTHON_VERSION=3.13.15` + image-pipeline
  Dockerfile builds `python:3.13.15-slim`. Needs one-direction decision.
  → superseded by the [M] 2026-08-23 approved-batch Done entry
  (standardized on Python 3.14.6).
- [M] 2026-08-23: Four Node service images build on node:24.x
  (web-shell/event-gateway-node/telemetry-element `node:24-alpine`; ocr-worker
  `node:24.6.0-bookworm-slim`) while every toolchain source pins
  `NODE_VERSION=26.6.0` (.nvmrc, versions.env). Runtime major bump decision.
  → superseded by the [M] 2026-08-23 approved-batch Done entry (images bumped
  to node:26.6.0).
- [M] 2026-08-23: scripts/projectstats.sh and scripts/push-images.sh have no
  Makefile target, doc reference, or caller (push-images duplicates in-script
  build+push inside smoke-test/build-images flow). Wire/document/remove decision.
  → superseded by the [S] 2026-08-24 Done entry (both scripts removed).

## In progress

<!-- being fixed -->

(none)

## Done

<!-- fixed and verified — keep the verification note -->

- [L] 2026-08-24 (PR-review round): sibling-event dedupe correctness. The
  adjudicator publishes one symbols-adjudicated event per symbol under a shared
  parent stepId, and image-pipeline compose consumers receive per-glyph events
  sharing one plan stepId, so naive stepId-keyed dedupe dropped siblings 2..N.
  phrase-assembler-rust register_token_step now keys step:attempt:position
  (AdjudicatedToken gained a serde-default attempt field) and image-pipeline
  accept_record keys event_type:position:attempt:stepId: redeliveries repeat all
  three (dropped) while quality retries bump only the attempt (accepted).
  Regression tests cover siblings + retry-vs-redelivery in both services;
  consumer.rb artifact tracing now covered by test/consumer_artifact_trace_test.rb
  (process_message-level fake-producer assertions; consumer require made portable).
  telemetry.cpp shutdown() pairs curl_global_cleanup with the one-shot init via
  an atomic flag (exchange(false)) and logs non-zero CURLcode. Verified
  2026-08-24: pre-commit gates exit=0, make integration failures=0 skipped=0.
- [L] 2026-08-24: lineage consistency family resolved per chain rule "emitted
  inputArtifacts = outputArtifacts of the consumed event; outputArtifacts = keys
  this step wrote". geometry-engine-cpp service.cpp now emits
  data.at("outputArtifacts") as inputArtifacts instead of its own blueprint copy
  key; adjudicator-ruby consumer.rb passes observations.outputArtifacts as
  inputArtifacts and emits outputArtifacts=[] (adjudicator writes no S3 keys);
  vector-normalizer-go verified already chain-correct (no change). Unit tests
  updated to assert traced values. Verified 2026-08-24: STRICT=1 format/lint/
  unit/coverage (94.91%)/contracts/contract-test PASS, make integration
  failures=0 skipped=0. Follow-up opened: ocr-worker-node consumer.ts echoes
  upstream outputArtifacts into its own event's outputArtifacts (same
  double-claiming pattern).
- [S] 2026-08-24: removed scripts/projectstats.sh + scripts/push-images.sh and
  their architecture.md file-tree reference (user disposition: remove; zero
  callers, push-images duplicated build-images.sh logic with a hardcoded image
  list). Verified by gates above.
- [M] 2026-08-24: geometry-engine-cpp exit-race SIGSEGV (found by integration
  gate): OTLP worker thread lazily initialized OpenSSL/libcurl from
  curl_easy_init while main thread was already inside atexit shutdown();
  OpenSSL registers its exit cleanup at first lazy init — after our shutdown
  handler — so LIFO teardown freed crypto locks under the running worker
  (~50% crash on --once). Fix: explicit curl_global_init on the main thread
  in telemetry::initialize() before spawning the worker + curl_global_cleanup
  after the join in shutdown() (telemetry.cpp). Verified: fresh build 40/40,
  repo binary 12/12 stress runs, STRICT=1 format/lint/unit/coverage/contracts/
  contract-test PASS, make integration failures=0 skipped=0.
- [M] 2026-08-23 (approved batch verified by integration gate 2026-08-24):
  assembler dedupe (step_id + register_token_step), image-pipeline lineage +
  pre-flush dedupe, dry-run literal removal, Python 3.14.6 standardization,
  Node 26.6.0 image bumps.
- [M] 2026-08-23: All "In progress" S/M doc/script items below verified by
  STRICT=1 format/lint/unit/coverage/build + contracts + contract-test
  (anti-cheat) all PASS on 2026-08-23; integration gate run separately.
- [M] image-pipeline-python bare prints → service logger (kafka_client.py,
  worker.py); 49/49 unittests.
- [M] rghw.sh RedisPassw0rd! fallback → loud skip when secret unreadable;
  bash -n clean.
- [M] rghw.sh one-off job pinned to MINIO_MC_VERSION=RELEASE.2025-08-13T08-35-41Z
  (versions.env); tag verified resolvable via docker manifest inspect.
- [M] README quick-start port-forwards corrected to svc ports (3000:80,
  3002:80, 8081:80).
- [M] Gateway SSE examples corrected to `/events/{runId}` with
  `?lastEventId=` replay; orchestrator stream noted for Last-Event-ID header
  (runbook §6.4, user-guide §§5.4/CLI).
- [S] runbook event-gateway probe `/healthz` → `/health`.
- [M] Hard-coded doc credentials replaced with secret-retrieval commands
  (runbook MinIO/PostgreSQL, user-guide MinIO Console/PostgreSQL).
- [M] OTel Collector version corrected to 0.128.0 (runbook, user-guide ×2).
- [S] Image count corrected 12 → 13 (runbook, user-guide).
- [S] Stale Makefile line references replaced with target names (runbook).
- [M] user-guide `rghw version` output corrected (`rghw 0.0.0-skeleton`).
- [M] user-guide §6.3 rewritten from each binary's real usage strings
  (compose/preprocess subcommands, positional OCR/adjudicator args,
  `--input=` for rust, glyph-catalog documented as SOAP-only).
- [S] runbook inspector landing-page self-contradiction removed.
- [S] artifact-inspector README upstream corrected to orchestrator.
- [S] glyph-catalog-java README pins synced to pom.xml (Boot 4.1.0, WS
  5.0.2, H2 2.4.240).
- [S] adjudicator-ruby README de-skeletonized; rake pin corrected to 13.4.2;
  Ruby floor 4.0+.
- [M] implementation-status known-deferred list now records CREATED,
  CANCELLED, and OUTPUT_MISMATCH as diagram-only states.
- [S] runbook Python version row now correct via approved standardization on
  PYTHON_VERSION=3.14.6 (versions.env + image-pipeline Dockerfile bumped;
  python:3.14.6-slim tag verified).

## Dropped (cycle 1 additions)

<!-- why: invalid, superseded, not reproducible -->

- [S] geometry-engine-cpp gcc base-image versions.env entry — invalid:
  versions.env lines 174-175 explicitly document that Temurin JVM and gcc
  images stay pinned inline in their Dockerfiles.

<!-- fixed and verified — keep the verification note -->

## Deferred

<!-- why: blocker, needs approval, too risky now -->

- [M] 2026-08-09: Java test runs report the terminally deprecated
  `sun.misc.Unsafe::objectFieldOffset` path from OpenTelemetry's shaded JCTools,
  plus Mockito's dynamically self-attached inline-mock-maker agent warning.
  The full pre-commit gate passes; this is dependency/test-runtime work rather
  than an application defect. Revisit on the next Java/OpenTelemetry/Mockito
  upgrade or before a JDK release that disables dynamic agent loading; prefer a
  supported dependency update or explicit test-agent configuration.
- [S] 2026-08-09: Artifact Inspector coverage reports Bundler/Ruby
  `Gem::Platform` constant redefinition warnings. Coverage passes at 95.34% and
  the warning is confined to the current Bundler/Ruby toolchain. Revisit during
  the next Ruby/Bundler dependency refresh and confirm the warning is gone.

## Dropped

<!-- why: invalid, superseded, not reproducible -->

- [S] 2026-08-23: smoke-test.sh literal phrase comparisons (lines 209,231,347)
  — dropped: verification harness equivalent to tests/ in spirit; anti-cheat
  allowlist passes it intentionally; relocating risks the smoke harness.
- [S] 2026-08-23: "Rube Goldberg Hello World" branding strings in web-shell
  App.tsx:170/index.html:6 and inspector HTML heredocs — dropped: project
  branding rendered to humans; integrity rule 7 targets the derivation chain,
  and the guard suite intentionally passes these.
- [S] 2026-08-23: adjudicator-ruby consumer reprocesses every delivery without
  a dedupe store — dropped for now: published ids are deterministic
  (`build_operation_id`), which is exactly rule 9's stated mechanism;
  revisit only with the image-pipeline dedupe decision.
- [S] 2026-08-23: adjudicator Gemfile bare stdlib-facade gems
  (base64/bigdecimal/delegate/logger) and `ruby '>= 3.4.0'` floors — dropped:
  lockfiles resolve exact versions (the effective pin); floors are Bundler
  convention.
- [S] 2026-08-23: event-gateway types.ts 'GEOMETRY_EXPANDING' "mismatch" —
  invalid finding: orchestrator maps GENERATING_GEOMETRY to external stage
  label GEOMETRY_EXPANDING (Application.kt:988,1177), so the type mirrors
  reality.
