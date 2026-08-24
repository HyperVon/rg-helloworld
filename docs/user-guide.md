# User Guide — Rube Goldberg Hello World

Practical guide to running the system, using every web UI, and understanding what each application does. For operations and bring-up, see [runbook.md](runbook.md); for the full design, see [architecture.md](architecture.md).

> **One-liner:** `./rghw.sh` (or `.\rghw.bat` on Windows) brings up the whole stack, prints `HELLO WORLD`, and leaves every UI on `http://localhost:3000` etc. Everything below explains what you are looking at.

## 1. What this system does (and why it is ridiculous)

You ask for `HELLO WORLD`. The system does not print a string literal. It:

1. Plans 11 glyph blueprints (10 letters + a gap) via SOAP
2. Expands them to raw geometry (C++)
3. Normalizes vectors to a 1000×1000 canvas (Go)
4. Rasterizes each glyph to a 128×128 PNG via gRPC (C#)
5. Composes the 11 rasters into one phrase image and preprocesses a second image for OCR (Python, 192 px/em)
6. Runs Tesseract OCR on 11 crops (Node)
7. Adjudicates the 11 noisy observations into symbols (Ruby, 0.30/0.40 thresholds)
8. Assembles the symbols into `HELLO WORLD` (Rust, with Whitespace provenance)

Every stage increases the maturity rank `0 → 10 → … → 100` and writes its artifact to MinIO (Kafka carries only references). The CLI streams progress on stderr and prints exactly `HELLO WORLD` on stdout.

If any stage shows `HE!|OMOBID` or similar in logs, it is a real OCR/adjudication failure, not a placeholder — adjust with `low-memory` or re-run.

## 2. Quick start — one command

Works on **macOS** (Intel & Apple Silicon + Colima), **Linux**, and **Windows 10/11** (Docker Desktop + WSL2/Git Bash). All flags work on all OS — `.\rghw.bat` delegates to `bash rghw.sh` when Git Bash is found, so `--quiet`/`--fresh` are identical everywhere. See [runbook §2](runbook.md#2-system-requirements--os-support) for RAM/disk/CPU.

```bash
./rghw.sh              # Linux/macOS: cluster → images → infra → deploy → wait → HELLO WORLD + URL table
.\rghw.bat             # Windows: same flags — delegates to bash rghw.sh when available
./rghw.sh --dry-run    # preview without executing
./rghw.sh --skip-images --skip-infra --open  # fast restart, open browser
./rghw.sh --quiet      # HELLO WORLD only on stdout
./rghw.sh --fresh --quiet  # clean previous runs (Redis+MinIO, preserves Kafka), then HELLO WORLD
```

Windows notes: use **Git Bash** or **WSL2** (`bash rghw.sh --quiet`) as primary; native `cmd.exe` fallback via `.\rghw.bat` also handles `--quiet`/`--fresh`/`--skip-images`/`--timeout`/`--api-url`. Requires Docker Desktop + WSL2, `k3d`/`kubectl`/`helm`/`terraform` on `PATH`, and `make` (`choco install make`). Port-forward mode needs no `/etc/hosts`; ingress needs `C:\Windows\System32\drivers\etc\hosts` entries only if you use `rghw.localhost`.

On success you see:

```text
[1/2] Creating run...
[2/2] Waiting for the orchestrator...
HELLO WORLD
```

and a URL table. Leave the terminal open — port-forwards stay alive. Stop them with `pkill -f 'kubectl port-forward -n rube-goldberg'` or `Ctrl-C` in the `rghw.sh` window.

Manual bring-up (what the script automates):

```bash
make prerequisites   # toolchain + npm ci / bundle / venv
make cluster         # k3d + registry localhost:5001
make images          # 12 images (glyph-catalog … web-shell)
make infra           # Terraform: Kafka, MinIO, Postgres, Redis, secrets
make deploy          # kubectl apply milestone 5-11 manifests
make wait            # 25 pods 1/1 Running
make run             # rghw run --api-url http://localhost:8080
```

## 3. The pipeline in plain English

| Stage | Application | Language | Input → Output | What you can see |
| --- | --- | --- | --- | --- |
| **CLI** | `rghw` | Go | request `HELLO WORLD` → orchestrator REST | Stderr progress, stdout `HELLO WORLD` |
| **Orchestrator** | `run-orchestrator` | Kotlin | `PLANNING → SUCCEEDED` state machine, fans out/in, validates maturity | Web Shell graph, `GET /api/v1/runs`, Grafana |
| **Glyph Catalog** | `glyph-catalog` | Java/SOAP | `HELLO WORLD` → 11 `Glyph` blueprints (gap at position 5, `GAP 0.6`) | Artifact Inspector → geometry JSON |
| **Geometry Engine** | `geometry-engine` | C++ | blueprints → expanded line geometry files | Inspector → `svgSha256` |
| **Vector Normalizer** | `vector-normalizer` | Go | geometry → normalized SVG (1000×1000, stroke 140) | Inspector → SVG preview |
| **Rasterizer** | `rasterizer` | C# gRPC | SVG → 128×128 PNG per glyph | Inspector → raster PNG |
| **Image Pipeline** | `image-pipeline` | Python | rasters → phrase PNG (2075×212) + OCR image (4190×464, border 16) | Inspector → phrase/OCR PNG |
| **OCR Worker** | `ocr-worker` | Node | OCR crops → `HE…` observations per position (60→70) | Grafana OCR Lab, Loki logs |
| **Adjudicator** | `adjudicator` | Ruby | observations → adjudicated symbols (70→80, `GAP` tokens) | Grafana Deep Dive, adjudicator logs |
| **Phrase Assembler** | `phrase-assembler` | Rust | adjudicated events → `HELLO WORLD` (80→90, Whitespace provenance) | `GET /api/v1/runs/{id}/artifacts` → `sha256` |
| **Event Gateway** | `event-gateway` | Node | Redis Stream → SSE `/api/v1/runs/{id}/stream` | Web Shell live, `curl -N` stream |
| **Telemetry** | `telemetry-element` | TypeScript Web Component | `<rg-telemetry-panel>` step ledger | Embedded in Web Shell |

Supporting: Kafka (13 topics `rg.*.v1`: 11 application topics + 2 infrastructure — `rg.run-events.v1`, `rg.dead-letter.v1`), Redis Streams (`rg:run:{id}:events`), MinIO (`rube-goldberg-artifacts`), PostgreSQL, OpenTelemetry Collector → Prometheus/Loki/Tempo → Grafana.

## 4. CLI — `rghw run` and friends

All commands are Go (`cmd/rghw`, module `rghw.dev/rghw`). Run from repo root or `go install`:

```bash
go -C cmd/rghw run . run --help          # via go run (no install)
rghw run --help                          # after go install
```

| Command | What it does | Example |
| --- | --- | --- |
| `rghw run` | Create a run for `HELLO WORLD` (default) and stream to `SUCCEEDED`, print `HELLO WORLD` | `rghw run --api-url http://localhost:8080` |
| `rghw run --message "HELLO WORLD"` | Explicit message (must be `HELLO WORLD` uppercase) | — |
| `rghw run --api-url http://rghw.localhost/api` | Ingress mode (default per architecture §21.4) | — |
| `rghw run --api-url http://localhost:8080 --timeout 3m` | Port-forward mode, custom timeout (exit 3 on timeout) | — |
| `rghw run --quiet` | Only `HELLO WORLD` on stdout, no stderr progress | `RESULT=$(rghw run --quiet)` |
| `rghw version` | `run-orchestrator 0.5.0-milestone11` | — |

**Stream contract:** stderr `[01/10] … [10/10] …` + URLs/runId; stdout **exactly** `HELLO WORLD\n` on exit 0 (so `test "$(rghw run --quiet)" = "HELLO WORLD"`). Exit codes: `0` success, `1` system, `2` invalid, `3` timeout, `4` OCR failed, `5` output mismatch, `130` cancelled.

Low-level checks:

```bash
curl -sf http://localhost:8080/healthz
curl -s http://localhost:8080/api/v1/runs | jq
curl -N -H "Accept: text/event-stream" http://localhost:8081/api/v1/runs/<id>/stream
```

## 5. Web UIs — what they are and how to use them

All UIs are in namespace `rube-goldberg`. Two access modes: **ingress** (`rghw.localhost` → add to `/etc/hosts`) or **port-forward** (`localhost:3000` etc. — recommended, no hosts edit). The table below is port-forward mode, which `rghw.sh` starts for you.

### 5.1 Web Shell — `http://localhost:3000` (React Flow, the flagship)

*Image:* `rghello-registry:5001/web-shell:milestone11` (`services/web-shell`)

**What it is:** A dark glass control plane that visualizes the 11-stage pipeline as a live DAG. It is the fastest way to answer “did my run succeed and where did it spend time?”

**How to use:**

1. Open `http://localhost:3000` — header shows `● Connected` when SSE is live.
2. Top bar has a **dropdown** — auto-populated via `GET /api/v1/runs` sorted `createdAt` desc (newest first, `8-char… — SUCCEEDED — 8/8/2026, 1:44:45 AM`), auto-selects the latest run and persists `localStorage.rghw:lastRunId`. Change selection to inspect an older run.
3. `Viewing: <full runId>` confirms which run the graph belongs to. `Clear` removes the stored id.
4. **Manual fallback** is behind `Or enter run ID manually` (collapsed `<details>`) — only needed if the list is empty.
5. **Process Graph** shows 11 nodes `Run Planning → … → Terminal` green `completed`, yellow `running`, grey `pending`. The current stage is in Telemetry below.
6. **Telemetry** shows `Attempt`, `Progress`, `Stage: SUCCEEDED/…`, `Events received`. On `SUCCEEDED`, `View Artifacts` opens a modal that fetches `GET /api/v1/runs/{id}/artifacts`.
7. No page reload needed — the graph animates via SSE; reload mid-run resumes via `Last-Event-ID`.

*If the dropdown is empty:* run `rghw run` or `go -C cmd/rghw run . run --api-url http://localhost:8080` first. The list polls every 5s.

### 5.2 Artifact Inspector — `http://localhost:3001` (Ruby + Sinatra templates)

*Image:* `artifact-inspector:milestone11` (`services/artifact-inspector-ruby`)

**What it is:** A gallery of every available intermediate artifact for a run, with SHA-256 lineage and run-scoped MinIO proxy links. Use it when the Web Shell says `FAILED` and you want to see which image or OCR step produced the bad input.

**How to use:**

1. Open `http://localhost:3001/` — dark card, `RG` logo, `Loading runs…` dropdown. It fetches `GET /api/v1/runs` (same sort as Web Shell) via `GET /api/v1/runs` proxied to the orchestrator (`ENV ORCHESTRATOR_URL`). Picks are `id… — status — date`, newest at top.
2. Select a run → `Open →` → `/inspector/runs/{runId}`. Equivalent to `http://localhost:3001/inspector`.
3. The run page shows a table `ID | Stage | SHA-256 (16) | View →`. Click `View →` for `contentType`, full `sha256`, and an opaque **proxy URL** (the orchestrator streams MinIO bytes without credentials in the HTML).
4. PNG and SVG artifacts render inline through the proxy; JSON artifacts remain available for inspection by content type.
5. Manual path still exists: `/` has `<details>Or enter run ID manually</details>` with an `Enter runId` form — useful when copying from `rghw run` stderr.
6. APIs you can call directly: `GET /api/v1/runs` (JSON list), `GET /inspector/runs/{id}/artifacts` (JSON), `GET /api/v1/runs/{id}/artifacts/{artifactId}` (artifact bytes), `GET /health` → `{"status":"ok"}`.

*If “No artifacts yet”* the run is still in `PREPROCESSING`/`OCR_RUNNING` — wait a few seconds and refresh, or watch the Web Shell graph.

### 5.3 Telemetry Panel — embedded in Web Shell

*Element:* `<rg-telemetry-panel>` (`services/telemetry-element`, TypeScript Web Component)

**What it is:** Dense numeric telemetry next to the graph — attempt table, duration table, OCR confidence, Kafka event counts, resource usage. It is not a separate page; it renders inside Web Shell’s Telemetry section. No extra port.

### 5.4 Event Gateway (SSE) — `http://localhost:8081`

*Image:* `event-gateway-node` (`services/event-gateway-node`, Redis Streams → SSE)

**What it is:** The raw event bus. The CLI and Web Shell both consume it; you can `curl` it to debug streaming.

**How to use:**

```bash
RUN_ID=$(curl -s http://localhost:8080/api/v1/runs | jq -r '.runs[0].runId')
curl -N -H "Accept: text/event-stream" http://localhost:8081/api/v1/runs/$RUN_ID/stream
# or via orchestrator directly
curl -N http://localhost:8080/api/v1/runs/$RUN_ID/stream
```

You see `: connected` then `data: {"status":"PLANNING"…}` etc., heartbeats `event:heartbeat` every 15s, and a final `data: {"status":"SUCCEEDED","assembledText":"HELLO WORLD"…}` after which the server closes. Mid-run reloads replay via `Last-Event-ID` — the gateway sends a snapshot first.

Health: `curl -s http://localhost:8081/health` → `{"status":"ok"}`.

### 5.5 Grafana — `http://localhost:3002` (4 dashboards)

*Image:* Grafana 12.0.2 (`infra/k8s/milestone11/grafana.yaml`, creds in secret `grafana-credentials`)

**What it is:** The observability story — not default dashboards. They are provisioned via ConfigMaps (`grafana-dashboards`, `grafana-provisioning` with `subPath` for `datasource.yml`/`dashboard.yml`), so they appear at `http://localhost:3002/dashboards` without manual import.

**How to use:**

1. `kubectl get secret grafana-credentials -n rube-goldberg -o jsonpath='{.data.admin-password}' | base64 -d; echo` → password, user `admin`.
2. Open `http://localhost:3002/login` → `admin` / `<password>` → Skip → Dashboards → filter `rube-goldberg`.
3. Four dashboards:
   - **Rube Goldberg Overview** (`rg-overview`) — `rg_runs_total`, `rg_active_runs`, stage durations, Kafka lag, artifact bytes
   - **Run Deep Dive** (`rg-deep-dive`, variable `trace_id`) — Tempo trace timeline + Loki logs + stage table
   - **OCR Laboratory** (`rg-ocr-lab`) — confidence by position/attempt, quality-rejection count, preprocessing foreground ratio
   - **Ridiculous Infrastructure** (`rg-infra`) — pod CPU/mem, Kafka/Postgres/Redis, MinIO, OTel queues
4. All dashboards are dark-themed and use Prometheus `http://prometheus:9090`, Loki `http://loki:3100`, Tempo `http://tempo:3200` (already provisioned, no manual datasource add).

Screenshots: `docs/screenshots/grafana*.png` (captured via Playwright at `SUCCEEDED`).

### 5.6 Prometheus, Loki, Tempo, OTel

*Images:* Prometheus 3.5, Loki 3.5.2, Tempo 2.4.0 (minimal local backend `/tmp/tempo/blocks`), OTel Collector 0.91

**Prometheus** `http://localhost:9090` (`/-/healthy` → `Prometheus Server is Healthy`) — valid PromQL (see runbook §6.1.2):

```promql
rg_runs_total
rg_runs_total{status="SUCCEEDED"}
rg_active_runs
rg_artifacts_created_total
sum(rg_artifacts_created_total) by (kind)
rate(rg_step_completed_total[5m])
rg_kafka_consumer_lag
up{job="kubernetes-pods"}
```

Quick check: `curl -s 'http://localhost:9090/api/v1/query?query=rg_runs_total' | jq .` → vector `1` after one run. Targets at `/targets` should all be `UP` (Kubernetes SD). Full list and curl probes: runbook §6.1.2 and §6.3.

**Loki** `http://localhost:3100` (`/ready` → `ready`) — view via Grafana Explore → Loki data source. All services log structured JSON with `traceId`/`spanId`.

**Tempo** `http://localhost:3200` (`/status` → `server listening http [::]:3200 grpc [::]:9095`) — one root span `rube-goldberg.run` per run with children `orchestrator.create-run`, `soap.plan-phrase`, `kafka.produce/consume`, `geometry.expand`, `grpc.render-glyph`, `image.compose`, `ocr.*`, `adjudicate.symbol`, `assemble.phrase`. Traces arrive via OTel Collector `otel-collector:4317` (gRPC). Inside Grafana, Run Deep Dive links Loki logs → Tempo.

**OTel Collector** `http://localhost:4317` gRPC / `4318` HTTP — `kubectl logs deploy/otel-collector -n rube-goldberg | grep "Everything is ready"` → `0.91.0`.

### 5.7 MinIO, Kafka, Redis, Postgres

**MinIO Console** `http://localhost:9000` (API) / `http://localhost:9001` if console enabled (`minio-console` svc) — bucket `rube-goldberg-artifacts`, keys like `phrase/<runId>/svg/<glyph>.svg` with SHA-256 sidecars. Login `minioadmin/minioadmin` (from `minio-credentials`). CLI:

```bash
mc alias set local http://localhost:9000 minioadmin minioadmin
mc ls -r local/rube-goldberg-artifacts
```

**Kafka** `localhost:9092` (KRaft, 3 controllers `kafka-controller-0/1/2`) — 13 topics `rg.*.v1` (11 application topics + 2 infrastructure: `rg.run-events.v1`, `rg.dead-letter.v1`); the application topics span `rg.glyph-blueprints.v1` (10→20) … `rg.phrase-assembled.v1` (80→90). No plaintext leaks: downstream events never contain `targetText`, `expectedCharacter` etc. (checked by unit + integration).

**Redis** `localhost:6379` (`redis-master`, streams `rg:run:{id}:events` backing SSE) — `redis-cli XLEN rg:run:<id>:events`.

**PostgreSQL** `localhost:5432` (`postgres-postgresql`, secret `postgres-credentials`, password `PostgresPassw0rd!`) — projections, not on the critical path. `psql -h localhost -U postgres`.

## 6. Running the applications — what to run when

### 6.1 Everyday (you just want HELLO WORLD and the UIs)

```bash
./rghw.sh --open          # or make demo
open http://localhost:3000  # Web Shell — pick latest run, watch graph → SUCCEEDED
open http://localhost:3001  # Inspector — pick same run, View → PNG/SVG
open http://localhost:3002  # Grafana — login admin / secret
```

### 6.2 CLI power uses

```bash
# quiet for scripts
[ "$(go -C cmd/rghw run . run --quiet --api-url http://localhost:8080)" = "HELLO WORLD" ] && echo ok

# custom timeout for slow clusters
go -C cmd/rghw run . run --timeout 5m --api-url http://localhost:8080
```

### 6.3 Service-level `--once` (for debugging a stage without Kafka/K8s)

Every service has a deterministic `--once` that reads one artifact and writes the next — used by integration tests (`tests/integration/run_integration.sh`) and handy locally:

```bash
# Java SOAP → blueprints (11)
java -jar services/glyph-catalog-java/target/glyph-catalog-*.jar --once --message "HELLO WORLD"

# C++ geometry expand (10→20)
./services/geometry-engine-cpp/build/geometry_engine --once --input /tmp/blueprints.json

# Go normalizer (20→30)
go -C services/vector-normalizer-go run . --once --input /tmp/geometry.json

# C# rasterizer via gRPC (--rasterizer-url for real server, else local)
dotnet run --project services/rasterizer-dotnet/cli -- --once --input /tmp/normalized.json

# Python compose (30→40→50) + preprocess (50→60)
PYTHONPATH=services/image-pipeline-python/src python -m rg_image_pipeline --once --stage compose
PYTHONPATH=services/image-pipeline-python/src python -m rg_image_pipeline --once --stage preprocess --phrase-image /tmp/phrase.png

# Node OCR (60→70)
node services/ocr-worker-node/out/index.js --once --ocr-image /tmp/ocr.png

# Ruby adjudicator (70→80)
ruby -Iservices/adjudicator-ruby/lib services/adjudicator-ruby/bin/adjudicator --once --observations /tmp/observations.json

# Rust assembler (80→90)
cargo run -p phrase-assembler -- --once --input /tmp/adjudicated.json

# Go + Rust together is how M9 verifies HELLO WORLD without a cluster:
# tests/integration/run_integration.sh sections 5.5–5.9
```

Each `--once` is idempotent (deterministic operation IDs) and validates `inputMaturity → outputMaturity` strictly increases, rejecting prohibited fields.

### 6.4 Observability one-liners

```bash
# traces
curl -s http://localhost:3200/status | jq .ingester
# metrics
curl -s http://localhost:9090/api/v1/query?query=rg_runs_total
# logs
curl -s "http://localhost:3100/loki/api/v1/labels" | jq
# minio
mc find local/rube-goldberg-artifacts --name "*.png" | head
```

## 7. Guardrails you will hit

- **No hard-coded `HELLO WORLD`** in downstream events or logs — search with `rg -n "HELLO WORLD" --glob '!**/*.md'` should only hit `cmd/rghw/internal/brainfuck/default.bf` (obfuscated) and tests. Downstream events are validated for prohibited fields.
- **Only CLI, orchestrator, and glyph catalog see the requested plaintext** before validation; adjudicator/assembler see only adjudicated symbols.
- **Idempotent Kafka consumers** — rerunning `--once` with same operation ID does not duplicate artifacts.
- **Large payloads in MinIO**, never in Kafka/Redis/logs.

## 8. Next steps

- **Runbook** for bring-up, port-forwards, low-memory, and recovery: [runbook.md](runbook.md)
- **Architecture** for contracts, maturity ranks, and sequence diagrams: [architecture.md](architecture.md) (§4 CLI, §20 observability, §25 orchestration)
- **Implementation status** for what is done and what was verified when: [implementation-status.md](implementation-status.md)
- **Troubleshooting** for ports, DiskPressure, Kafka rebalancing, MinIO: [troubleshooting.md](troubleshooting.md)
- **Screenshots** (all Playwright 1280×800 at `SUCCEEDED`): [screenshots/](screenshots/). *Note: screenshots were captured 2026-08-08; refresh them after the current UI stabilizes.*

If a UI shows `PREPROCESSING` stuck with `Progress: 0%`, it is a real pipeline delay (Kafka rebalancing or OCR) — wait 30s and refresh, or check `kubectl logs deploy/ocr-worker -n rube-goldberg` and `kubectl get pods`.
