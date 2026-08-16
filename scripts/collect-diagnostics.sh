#!/usr/bin/env bash
# Collect diagnostics for the rube-goldberg stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="rube-goldberg"
OUT=".local/diagnostics"
mkdir -p "$OUT"

# shellcheck source=scripts/infra-selectors.sh
source "$ROOT/scripts/infra-selectors.sh"

say() { echo "[diagnostics] $*"; }
warn() { echo "[diagnostics] WARN: $*" >&2; }

say "Collecting pod logs..."
kubectl get pods -n "$NS" -o wide > "$OUT/pods.txt" 2>&1 || true
for pod in $(kubectl get pods -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl logs -n "$NS" pod/"$pod" --tail=100 > "$OUT/${pod}.log" 2>&1 || true
done

say "Collecting events..."
kubectl get events -n "$NS" --sort-by='.lastTimestamp' > "$OUT/events.txt" 2>&1 || true

# collect_infra SELECTOR OUTFILE -- CMD ARGS...
# Resolve the dependency pod via the shared selector list and run CMD inside it.
# Warns (instead of silently || true) when the selector resolves to no pod, or
# when the exec fails, so diagnostics are not quietly empty when most needed.
collect_infra() {
  local selector="$1"
  local outfile="$2"
  shift 2
  local pod
  pod=$(resolve_infra_pod "$selector" "$NS")
  if [ -z "$pod" ]; then
    warn "no pod resolved for selector=$selector; skipping $outfile"
    return 0
  fi
  say "Collecting $selector via $pod..."
  if ! kubectl exec -n "$NS" "$pod" -- "$@" > "$OUT/$outfile" 2>&1; then
    warn "exec failed for $selector (pod=$pod); $outfile may be empty"
  fi
}

say "Collecting Kafka consumer groups..."
collect_infra kafka-controller kafka-consumer-groups.txt kafka-consumer-groups.sh --bootstrap-server localhost:9092 --describe --all-groups

say "Collecting MinIO bucket inventory..."
collect_infra minio minio-artifacts.txt mc ls -r local/rube-goldberg-artifacts

say "Collecting PostgreSQL connections..."
collect_infra postgres-postgresql postgres-connections.txt psql -U postgres -c "SELECT * FROM pg_stat_activity;"

say "Collecting Redis info..."
collect_infra redis-master redis-info.txt redis-cli INFO

say "Diagnostics collected in $OUT"
