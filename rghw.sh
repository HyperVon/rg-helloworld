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
QUIET=0
FRESH=0

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

say() { [[ $QUIET -eq 1 ]] && return; echo -e "${CYAN}[rghw]${NC} $*" >&2; }
ok()  { [[ $QUIET -eq 1 ]] && return; echo -e "${GREEN}[ok]${NC} $*" >&2; }
warn(){ [[ $QUIET -eq 1 ]] && return; echo -e "${YELLOW}[warn]${NC} $*" >&2; }
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
  --quiet, --silent Only print HELLO WORLD to stdout (suppress progress/URL table)
  --fresh           Clean existing rube-goldberg state before bring-up (kill forwards + delete namespace)

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
  Web Shell (React Flow) : http://rghw.localhost/                -> http://localhost:3000  (enter runId; /api proxied to orchestrator:8080)
  Artifact Inspector     : http://rghw.localhost/inspector/runs/{runId} -> http://localhost:3001/ (or /inspector; enter runId)
  Event Gateway (SSE)    : http://rghw.localhost/api/v1/runs/{runId}/stream -> http://localhost:8081 (svc/event-gateway, also via orchestrator:8080)
  Grafana                : http://grafana.rghw.localhost/       -> http://localhost:3002
  Prometheus             :                                        -> http://localhost:9090
  Loki                   :                                        -> http://localhost:3100
  Tempo                  :                                        -> http://localhost:3200
  MinIO (API)            : http://minio.rghw.localhost/         -> http://localhost:9000
  Orchestrator API       : http://rghw.localhost/api/v1/runs    -> http://localhost:8080

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
    --quiet|--silent) QUIET=1; shift ;;
    --fresh) FRESH=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --timeout=*) TIMEOUT="${1#*=}"; shift ;;
    --api-url) API_URL="$2"; shift 2 ;;
    --api-url=*) API_URL="${1#*=}"; shift ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

print_urls() {
  [[ $QUIET -eq 1 ]] && return
  cat <<URLS

${BOLD}Web URLs -- Rube Goldberg Hello World${NC}
${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
  ${BOLD}Web Shell (React Flow)${NC}   Ingress: ${GREEN}http://rghw.localhost/${NC}
                              Port-fwd: ${GREEN}http://localhost:3000/${NC}   (svc/web-shell)  -- enter runId after run
  ${BOLD}Artifact Inspector${NC}       Ingress: ${GREEN}http://rghw.localhost/inspector/runs/{runId}${NC}
                              Port-fwd: ${GREEN}http://localhost:3001/${NC}   (svc/artifact-inspector) -- shows form, then /inspector/runs/{runId}
  ${BOLD}Event Gateway (SSE)${NC}      Ingress: ${GREEN}http://rghw.localhost/api/v1/runs/{runId}/stream${NC}
                              Port-fwd: ${GREEN}http://localhost:8081${NC}   (svc/event-gateway)
                              CLI/API:${GREEN}http://localhost:8080/api/v1/runs${NC} (svc/run-orchestrator) -- also serves stream
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
  [[ $QUIET -eq 1 ]] && return
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
  if [[ $QUIET -eq 1 ]]; then
    echo "HELLO WORLD"
    exit 0
  fi
  say "Dry run -- would execute:"
  echo "  make prerequisites"
  echo "  make cluster"
  if [[ $SKIP_IMAGES -eq 0 ]]; then echo "  make images"; else echo "  (skip) make images"; fi
  if [[ $SKIP_INFRA -eq 0 ]]; then echo "  make infra"; else echo "  (skip) make infra"; fi
  echo "  make wait"
  echo "  kubectl port-forward x8 (web-shell:3000->80, event-gateway:8081->80, artifact-inspector:3001->80, grafana:3002->80, prometheus:9090, loki:3100, tempo:3200, minio:9000, orchestrator:8080)"
  echo "  rghw run --api-url $API_URL --timeout $TIMEOUT"
  print_urls
  exit 0
fi

if [[ $FRESH -eq 1 ]]; then
  say "Fresh mode -- cleaning existing rube-goldberg state..."
  pkill -f "kubectl port-forward -n $NAMESPACE" 2>/dev/null || true
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti tcp:3000,3001,8080,8081,3002,9090,3100,3200,9000 2>/dev/null | xargs kill -9 2>/dev/null || true
  fi
  if [[ $QUIET -eq 1 ]]; then
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait --timeout=60s >/tmp/rghw-fresh.log 2>&1 || true
  else
    kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait --timeout=60s 2>&1 | sed 's/^/[fresh] /' >&2 || true
  fi
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
  if [[ $QUIET -eq 1 ]]; then
    bash "$PROJECT_ROOT/scripts/prerequisites.sh" >/tmp/rghw-prereq.log 2>&1 || true
  else
    say "Checking prerequisites..."
    bash "$PROJECT_ROOT/scripts/prerequisites.sh" || warn "prerequisites reported issues (ignored, CI runs STRICT=1)"
  fi
fi

# 2. Cluster
if [[ $QUIET -eq 1 ]]; then
  if ! make -C "$PROJECT_ROOT" cluster >/tmp/rghw-make-cluster.log 2>&1; then
    if kubectl get nodes 2>/dev/null | grep -q " Ready " && kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -q "Running"; then
      : # usable despite timeout, continue silently
    else
      die "make cluster failed and cluster not ready — check docker/colima and k3d (see /tmp/rghw-make-cluster.log)"
    fi
  fi
else
  say "Ensuring k3d cluster '$NAMESPACE'..."
  if ! make -C "$PROJECT_ROOT" cluster; then
    warn "make cluster reported timeout (often due to Completed jobs) — checking if cluster is still usable..."
    if kubectl get nodes 2>/dev/null | grep -q " Ready " && kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -q "Running"; then
      warn "Cluster node is Ready and rube-goldberg pods are Running — continuing despite make cluster timeout"
    else
      die "make cluster failed and cluster not ready — check docker/colima and k3d"
    fi
  fi
fi

# 3. Images
if [[ $QUIET -eq 1 ]]; then
  if [[ $SKIP_IMAGES -eq 0 ]]; then
    make -C "$PROJECT_ROOT" images >/tmp/rghw-make-images.log 2>&1 || die "make images failed (see /tmp/rghw-make-images.log)"
  fi
else
  if [[ $SKIP_IMAGES -eq 0 ]]; then
    say "Building and pushing images to localhost:5001 (this may take a few minutes)..."
    make -C "$PROJECT_ROOT" images || die "make images failed"
  else
    say "Skipping make images (--skip-images)"
  fi
fi

# 4. Infra
if [[ $QUIET -eq 1 ]]; then
  if [[ $SKIP_INFRA -eq 0 ]]; then
    make -C "$PROJECT_ROOT" infra >/tmp/rghw-make-infra.log 2>&1 || die "make infra failed (see /tmp/rghw-make-infra.log)"
  fi
else
  if [[ $SKIP_INFRA -eq 0 ]]; then
    say "Applying Terraform infra..."
    make -C "$PROJECT_ROOT" infra || die "make infra failed"
  else
    say "Skipping make infra (--skip-infra)"
  fi
fi

# 4b. Deploy app services
if [[ $QUIET -eq 1 ]]; then
  make -C "$PROJECT_ROOT" deploy >/tmp/rghw-make-deploy.log 2>&1 || die "make deploy failed (see /tmp/rghw-make-deploy.log)"
else
  say "Deploying app services (milestones 5-11)..."
  make -C "$PROJECT_ROOT" deploy || die "make deploy failed"
fi

# 5. Wait
if [[ $QUIET -eq 1 ]]; then
  make -C "$PROJECT_ROOT" wait >/tmp/rghw-make-wait.log 2>&1 || die "Cluster not ready (see /tmp/rghw-make-wait.log)"
else
  say "Waiting for pods to be Ready (300s)..."
  make -C "$PROJECT_ROOT" wait || {
    warn "make wait timed out -- dumping pod status"
    kubectl get pods -n "$NAMESPACE" || true
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -n 20 || true
    die "Cluster not ready"
  }
  ok "All pods Ready"
fi

# 6. Port-forwards (background)
if [[ $QUIET -eq 0 ]]; then
  say "Starting port-forwards for web UIs (background)..."
fi
declare -a PF_PIDS=()
declare -a PF_SVCS=()
pf() {
  local svc="$1" local_port="$2" remote_port="$3"
  # free local port if still bound from previous run
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti tcp:"$local_port" 2>/dev/null | xargs kill -9 2>/dev/null || true
  fi
  # shellcheck disable=SC2086
  kubectl port-forward -n "$NAMESPACE" svc/"$svc" ${local_port}:${remote_port} >/tmp/rghw-pf-${svc}.log 2>&1 &
  local pid=$!
  PF_PIDS+=($pid)
  PF_SVCS+=("$svc:$local_port->$remote_port")
  # give it a moment and warn if it died immediately
  sleep 0.8
  if ! kill -0 "$pid" 2>/dev/null; then
    warn "port-forward $svc $local_port->$remote_port died quickly — see /tmp/rghw-pf-${svc}.log (retrying once)"
    sleep 1
    kubectl port-forward -n "$NAMESPACE" svc/"$svc" ${local_port}:${remote_port} >/tmp/rghw-pf-${svc}.log 2>&1 &
    pid=$!
    PF_PIDS[-1]=$pid
  fi
  if [[ $QUIET -eq 0 ]]; then
    say "  $svc  $local_port->$remote_port  pid $pid"
  fi
}

pf run-orchestrator 8080 8080
pf web-shell 3000 80
pf event-gateway 8081 80
pf artifact-inspector 3001 80
pf grafana 3002 80
pf prometheus 9090 9090
pf loki 3100 3100
pf tempo 3200 3200
pf minio 9000 9000

if [[ $QUIET -eq 0 ]]; then
  sleep 3
  # summarize -- don't use `jobs` (shows unexpanded function body); use PIDs we tracked + pgrep
  ok "Port-forwards up (logs: /tmp/rghw-pf-*.log)"
  for i in "${!PF_PIDS[@]}"; do
    pid="${PF_PIDS[$i]}"
    svc="${PF_SVCS[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      echo "  [$((i+1))] $svc pid $pid Running" >&2
    else
      echo "  [$((i+1))] $svc pid $pid not running — check /tmp/rghw-pf-${svc%%:*}.log" >&2
    fi
  done
  kubectl get pods -n "$NAMESPACE" 2>&1 | head -n 5 >&2 || true
else
  sleep 3
fi

print_urls

# 7. Run rghw
if [[ $QUIET -eq 0 ]]; then
  say "Running rghw -- this will print HELLO WORLD to stdout and progress to stderr..."
fi
RGHW_QUIET_FLAG=""
if [[ $QUIET -eq 1 ]]; then
  RGHW_QUIET_FLAG=" --quiet"
fi
set +e
if [[ -x "$PROJECT_ROOT/cmd/rghw/rghw" ]]; then
  # shellcheck disable=SC2086
  "$PROJECT_ROOT/cmd/rghw/rghw" run --api-url "$API_URL" --timeout "$TIMEOUT"$RGHW_QUIET_FLAG
  RC=$?
elif command -v go >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT/cmd/rghw" && go run . run --api-url "$API_URL" --timeout "$TIMEOUT"$RGHW_QUIET_FLAG)
  RC=$?
else
  warn "Go not found and no binary at cmd/rghw/rghw -- trying 'make run'"
  make -C "$PROJECT_ROOT" run
  RC=$?
fi
set -e

if [[ $RC -eq 0 ]]; then
  if [[ $QUIET -eq 0 ]]; then
    ok "rghw run succeeded -- stdout was HELLO WORLD"
  fi
else
  warn "rghw run exited $RC -- check orchestrator logs: kubectl logs -n $NAMESPACE deploy/run-orchestrator | tail -n 100"
fi

print_urls

if [[ $OPEN_BROWSER -eq 1 ]]; then
  say "Opening browser tabs..."
  open_urls
fi

if [[ $QUIET -eq 0 ]]; then
  say "Port-forwards still running in background:"
  for i in "${!PF_PIDS[@]}"; do
    pid="${PF_PIDS[$i]}"
    svc="${PF_SVCS[$i]}"
    if kill -0 "$pid" 2>/dev/null; then
      echo "  [$((i+1))] $svc pid $pid Running" >&2
    else
      echo "  [$((i+1))] $svc pid $pid not running — check /tmp/rghw-pf-${svc%%:*}.log" >&2
    fi
  done
  say "Stop with:  kill ${PF_PIDS[*]}  # or: pkill -f 'kubectl port-forward -n $NAMESPACE'"
  say "Re-run:     ./rghw.sh --skip-images --skip-infra  # fast restart"
  say "Logs:       tail -f /tmp/rghw-pf-*.log"
  say "Docs:       docs/runbook.md section 6 for full UI catalog"
fi

exit $RC
