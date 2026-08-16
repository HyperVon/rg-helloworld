#!/usr/bin/env bash
# Milestone 12 chaos test: validate system behavior under component failures.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="rube-goldberg"

say() { echo "[chaos] $*"; }

check_pods_ready() {
  local not_ready
  not_ready=$(kubectl get pods -n "$NS" -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . | tr -d ' ')
  if [ "$not_ready" -gt 0 ]; then
    say "FAIL: $not_ready pods not in Running state"
    kubectl get pods -n "$NS" -o wide
    exit 1
  fi
  say "All pods ready"
}

check_service_healthy() {
  local svc="$1"
  local pod
  pod=$(kubectl get pods -n "$NS" -l "app=$svc" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$pod" ]; then
    say "FAIL: no pod found for $svc"
    exit 1
  fi
  kubectl logs -n "$NS" pod/"$pod" --tail=5 2>/dev/null | grep -qi "error\|panic\|fatal" && {
    say "FAIL: $svc pod logs show errors"
    exit 1
  }
  say "$svc healthy"
}

kill_random_pod() {
  local label="$1"
  local pods
  pods=$(kubectl get pods -n "$NS" -l "$label" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
  if [ -z "$pods" ]; then
    say "SKIP: no pods found for $label"
    return 0
  fi
  local pod
  pod=$(echo "$pods" | tr ' ' '\n' | shuf -n 1)
  say "Killing pod: $pod"
  kubectl delete pod -n "$NS" "$pod" --grace-period=0 --force 2>/dev/null || true
}

wait_for_recovery() {
  local label="$1"
  local timeout="${2:-120}"
  say "Waiting for $label recovery (timeout ${timeout}s)..."
  local deadline
  deadline=$(($(date +%s) + timeout))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local ready
    ready=$(kubectl get pods -n "$NS" -l "$label" -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -c . | tr -d ' ')
    if [ "$ready" -gt 0 ]; then
      say "$label recovered"
      return 0
    fi
    sleep 5
  done
  say "FAIL: $label did not recover within ${timeout}s"
  exit 1
}

verify_run_completes() {
  say "Verifying run completes after chaos..."
  local output
  output=$(cd "$ROOT/cmd/rghw" && go run . run --api-url "http://localhost:8080" 2>&1) || {
    say "FAIL: run failed after chaos: $output"
    exit 1
  }
  if ! echo "$output" | grep -q "HELLO WORLD"; then
    say "FAIL: run did not produce expected output after chaos (expected HELLO WORLD)"
    exit 1
  fi
  say "Run completed successfully after chaos (HELLO WORLD)"
}

main() {
  say "Starting chaos test suite"
  check_pods_ready

  # Phase 1: Kill a worker pod
  kill_random_pod "app=ocr-worker"
  wait_for_recovery "app=ocr-worker" 120
  sleep 10
  check_pods_ready

  # Phase 2: Kill an adjudicator pod
  kill_random_pod "app=adjudicator"
  wait_for_recovery "app=adjudicator" 120
  sleep 10
  check_pods_ready

  # Phase 3: Kill a data pod
  kill_random_pod "app=kafka"
  wait_for_recovery "app=kafka" 180
  sleep 15
  check_pods_ready

  # Phase 4: Verify system still works
  verify_run_completes

  say "Chaos test suite PASSED"
}

main "$@"
