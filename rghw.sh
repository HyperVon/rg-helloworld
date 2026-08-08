#!/usr/bin/env bash
set -euo pipefail

# Rube Goldberg Hello World -- one-command demo
# Starts the k3d cluster, builds images, applies infra, waits for pods,
# starts port-forwards, runs `rghw run`, and prints every web URL.
#
# Usage:
#   ./rghw.sh              # full bring-up + run, keep port-forwards
#   ./rghw.sh --help       # this help
#   ./rghw.sh --skip-images# reuse existing images (faster)
#   ./rghw.sh --skip-infra # skip terraform apply (cluster already provisioned)
#   ./rghw.sh --open       # open browser tabs after run
#   ./rghw.sh --timeout 90s# override rghw run timeout
#   ./rghw.sh --dry-run    # print what would be done, don't run

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="rube-goldberg"
API_URL="http://localhost:8080"
TIMEOUT="3m"
SKIP_IMAGES=0
SKIP_INFRA=0
OPEN_BROWSER=0
DRY_RUN=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

say() { echo -e "${CYAN}[rghw]${NC} $*"; }
ok()  { echo -e "${GREEN}[ok]${NC} $*"; }
warn(){ echo -e "${YELLOW}[warn]${NC} $*"; }
die() { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
rghw.sh -- one-command demo for Rube Goldberg Hello World

Usage:
  ./rghw.sh [options]

Options:
  --help            Show this help
  --skip-images     Skip `make images` (reuse registry)
  --skip-infra      Skip `make infra` (reuse terraform state)
  --open            Open browser tabs for Web Shell, Grafana, etc. after run
  --timeout D       rghw run timeout (default: 3m)
  --dry-run         Print plan and URLs without executing
  --api-url URL     Override orchestrator URL (default: http://localhost:8080)

What it does:
  1. make prerequisites (if needed) / checks colima on macOS
  2. make cluster  (k3d + registry localhost:5001, idempotent)
  3. make images   (unless --skip-images)
  4. make infra    (unless --skip-infra, terraform apply)
  5. make wait     (kubectl wait Ready 300s)
  6. kubectl port-forward for all web UIs (background)
  7. rghw run      (prints HELLO WORLD to stdout, progress to stderr)
  8. Prints URL table (ingress vs port-forward) and leaves forwards running

Web UIs (after port-forwards):
  Web Shell (React Flow) : http://rghw.localhost/          -> http://localhost:3000
  Artifact Inspector     : http://rghw.localhost/inspector/ -> http://localhost:3001
  Event Gateway (SSE)    : http://rghw.localhost/api/       -> http://localhost:8081
  Grafana                : http://grafana.rghw.localhost/   -> http://localhost:3002
  Prometheus             :                                    -> http://localhost:9090
  Loki                   :                                    -> http://localhost:3100
  Tempo                  :                                    -> http://localhost:3200
  MinIO (API)            : http://minio.rghw.localhost/     -> http://localhost:9000
  Orchestrator API       : http://rghw.localhost/api/       -> http://localhost:8080

Stop forwards:  jobs          # list
                kill %1 %2... # or pkill -f "kubectl port-forward -n rube-goldberg"

See docs/runbook.md for full manual steps.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --skip-images) SKIP_IMAGES=1; shift ;;
    --skip-infra) SKIP_INFRA=1; shift ;;
    --open) OPEN_BROWSER=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --api-url) API_URL="$2"; shift 2 ;;
    --api-url=*) API_URL="${1#*=}"; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

print_urls() {
  cat <<URLS

${BOLD}Web URLs -- Rube Goldberg Hello World${NC}
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  ${BOLD}Web Shell (React Flow)${NC}   Ingress: ${GREEN}http://rghw.localhost/${NC}
                              Port-fwd: ${GREEN}http://localhost:3000${NC}   (svc/web-shell)
  ${BOLD}Artifact Inspector${NC}       Ingress: ${GREEN}http://rghw.localhost/inspector/${NC}
                              Port-fwd: ${GREEN}http://localhost:3001${NC}   (svc/artifact-inspector)
  ${BOLD}Event Gateway (SSE)${NC}      Ingress: ${GREEN}http://rghw.localhost/api/v1/runs/{runId}/stream${NC}
                              Port-fwd: ${GREEN}http://localhost:8081${NC}   (svc/event-gateway)
                              CLI:    ${GREEN}http://localhost:8080${NC}   (svc/run-orchestrator)
  ${BOLD}Grafana${NC}                  Ingress: ${GREEN}http://grafana.rghw.localhost/${NC}
                              Port-fwd: ${GREEN}http://localhost:3002${NC}   (svc/grafana)
  ${BOLD}Prometheus${NC}               Port-fwd: ${GREEN}http://localhost:9090${NC}   (svc/prometheus)  -> /-/healthy
  ${BOLD}Loki${NC}                     Port-fwd: ${GREEN}http://localhost:3100${NC}   (svc/loki)        -> /ready
  ${BOLD}Tempo${NC}                    Port-fwd: ${GREEN}http://localhost:3200${NC}   (svc/tempo)       -> /status
  ${BOLD}MinIO (artifacts)${NC}        Ingress: ${GREEN}http://minio.rghw.localhost/${NC}
                              Port-fwd: ${GREEN}http://localhost:9000${NC}   (svc/minio) minioadmin/minioadmin
  ${BOLD}OTel Collector${NC}           Port-fwd: ${GREEN}grpc://localhost:4317${NC} / ${GREEN}http://localhost:4318${NC}

  ${YELLOW}Ingress requires /etc/hosts:${NC}  127.0.0.1 rghw.localhost grafana.rghw.localhost minio.rghw.localhost
  ${YELLOW}Port-forward needs no hosts file${NC} -- use the localhost: ports above.
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  ${BOLD}Next:${NC}  ./rghw.sh --open   # open browser
          kubectl get pods -n $NAMESPACE
          make diagnostics   # -> .local/diagnostics/

URLS
}

open_urls() {
  local urls=(
    "http://localhost:3000"
    "http://localhost:3001"
    "http://localhost:3002"
    "http://localhost:9090"
  )
  for u in "${urls[@]}"; do
    if command -v open >/dev/null 2>&1; then open "$u" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$u" >/dev/null 2>&1 || true
    elif command -v start >/dev/null 2>&1; then start "$u" >/dev/null 2>&1 || true
    fi
  done
}

if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry run -- would execute:"
  echo "  make prerequisites"
  echo "  make cluster"
  if [[ $SKIP_IMAGES -eq 0 ]]; then echo "  make images"; else echo "  (skip) make images"; fi
  if [[ $SKIP_INFRA -eq 0 ]]; then echo "  make infra"; else echo "  (skip) make infra"; fi
  echo "  make wait"
  echo "  kubectl port-forward x8 (web-shell:3000, event-gateway:8081, artifact-inspector:3001, grafana:3002, prometheus:9090, loki:3100, tempo:3200, minio:9000, orchestrator:8080)"
  echo "  rghw run --api-url $API_URL --timeout $TIMEOUT"
  print_urls
  exit 0
fi

say "${BOLD}Rube Goldberg Hello World -- demo${NC} (timeout $TIMEOUT, api $API_URL)"

# Colima hint on macOS
if [[ "$(uname -s)" == "Darwin" ]] && command -v colima >/dev/null 2>&1; then
  if ! colima status >/dev/null 2>&1; then
    warn "Colima not running -- starting 'colima start --cpu 4 --memory 8 --disk 40' ..."
    colima start --cpu 4 --memory 8 --disk 40 || warn "colima start failed, trying anyway"
  fi
fi

# 1. Prerequisites (best-effort)
if [[ -x "$PROJECT_ROOT/scripts/prerequisites.sh" ]]; then
  say "Checking prerequisites..."
  bash "$PROJECT_ROOT/scripts/prerequisites.sh" || warn "prerequisites reported issues (ignored, CI runs STRICT=1)"
fi

# 2. Cluster
say "Ensuring k3d cluster '$NAMESPACE'..."
if ! make -C "$PROJECT_ROOT" cluster; then
  warn "make cluster reported timeout (often due to Completed jobs) — checking if cluster is still usable..."
  if kubectl get nodes 2>/dev/null | grep -q " Ready " && kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -q "Running"; then
    warn "Cluster node is Ready and rube-goldberg pods are Running — continuing despite make cluster timeout"
  else
    die "make cluster failed and cluster not ready — check docker/colima and k3d"
  fi
fi

# 3. Images
if [[ $SKIP_IMAGES -eq 0 ]]; then
  say "Building and pushing images to localhost:5001 (this may take a few minutes)..."
  make -C "$PROJECT_ROOT" images || die "make images failed"
else
  say "Skipping make images (--skip-images)"
fi

# 4. Infra
if [[ $SKIP_INFRA -eq 0 ]]; then
  say "Applying Terraform infra..."
  make -C "$PROJECT_ROOT" infra || die "make infra failed"
else
  say "Skipping make infra (--skip-infra)"
fi

# 5. Wait
say "Waiting for pods to be Ready (300s)..."
make -C "$PROJECT_ROOT" wait || {
  warn "make wait timed out -- dumping pod status"
  kubectl get pods -n "$NAMESPACE" || true
  kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -n 20 || true
  die "Cluster not ready"
}
ok "All pods Ready"

# 6. Port-forwards (background)
say "Starting port-forwards for web UIs (background)..."
declare -a PF_PIDS=()
pf() {
  local svc="$1" local_port="$2" remote_port="$3"
  lsof -ti tcp:"$local_port" 2>/dev/null | xargs kill -9 2>/dev/null || true
  # shellcheck disable=SC2086
  kubectl port-forward -n "$NAMESPACE" svc/"$svc" ${local_port}:${remote_port} >/tmp/rghw-pf-${svc}.log 2>&1 &
  PF_PIDS+=($!)
  say "  $svc  $local_port->$remote_port  pid $!"
}

pf run-orchestrator 8080 8080
pf web-shell 3000 80
pf event-gateway 8081 8080
pf artifact-inspector 3001 80
pf grafana 3002 3000
pf prometheus 9090 9090
pf loki 3100 3100
pf tempo 3200 3200
pf minio 9000 9000

sleep 3
ok "Port-forwards up (logs: /tmp/rghw-pf-*.log)"
kubectl get pods -n "$NAMESPACE" | head -n 5 || true

print_urls

# 7. Run rghw
say "Running rghw -- this will print HELLO WORLD to stdout and progress to stderr..."
set +e
if [[ -x "$PROJECT_ROOT/cmd/rghw/rghw" ]]; then
  "$PROJECT_ROOT/cmd/rghw/rghw" run --api-url "$API_URL" --timeout "$TIMEOUT"
  RC=$?
elif command -v go >/dev/null 2>&1; then
  (cd "$PROJECT_ROOT/cmd/rghw" && go run . run --api-url "$API_URL" --timeout "$TIMEOUT")
  RC=$?
else
  warn "Go not found and no binary at cmd/rghw/rghw -- trying 'make run'"
  make -C "$PROJECT_ROOT" run
  RC=$?
fi
set -e

if [[ $RC -eq 0 ]]; then
  ok "rghw run succeeded -- stdout was HELLO WORLD"
else
  warn "rghw run exited $RC -- check orchestrator logs: kubectl logs -n $NAMESPACE deploy/run-orchestrator | tail -n 100"
fi

print_urls

if [[ $OPEN_BROWSER -eq 1 ]]; then
  say "Opening browser tabs..."
  open_urls
fi

say "Port-forwards still running in background (jobs):"
jobs || pgrep -a "kubectl port-forward" || true
say "Stop with:  kill ${PF_PIDS[*]}  # or: pkill -f 'kubectl port-forward -n $NAMESPACE'"
say "Re-run:     ./rghw.sh --skip-images --skip-infra  # fast restart"
say "Logs:       tail -f /tmp/rghw-pf-*.log"
say "Docs:       docs/runbook.md section 6 for full UI catalog"

exit $RC
