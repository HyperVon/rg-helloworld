#!/usr/bin/env bash
#
# rghw-portforward.sh — forward the local CLI to the real API port.
#
# `make run` points the CLI at RGHW_API_URL (default http://localhost:18080).
# traefik is disabled and nothing forwards 8080, so this script opens the
# port-forward that the run-orchestrator service actually listens on:
#   svc/run-orchestrator :8080  ->  localhost:18080
#
# The local/container ports are read from the live cluster when available and
# otherwise default to the values used by scripts/smoke-test.sh (18080:8080).
set -uo pipefail

NAMESPACE="${RGHW_NAMESPACE:-rube-goldberg}"
LOCAL_PORT="${RGHW_API_LOCAL_PORT:-18080}"
SVC="${RGHW_API_SVC:-run-orchestrator}"
CONTAINER_PORT="${RGHW_API_CONTAINER_PORT:-8080}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "rghw-portforward: kubectl not found; cannot set up port-forward" >&2
  exit 1
fi

if ! kubectl get svc "$SVC" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "rghw-portforward: service '${SVC}' not found in namespace '${NAMESPACE}'" >&2
  echo "rghw-portforward: is the cluster up? (make cluster && make deploy)" >&2
  exit 1
fi

# Prefer the real container port published by the service when discoverable.
discovered="$(kubectl get svc "$SVC" -n "$NAMESPACE" \
  -o 'go-template={{range.spec.ports}}{{if eq .name "http"}}{{.port}}{{end}}{{end}}' 2>/dev/null)"
if [ -n "$discovered" ]; then
  CONTAINER_PORT="$discovered"
fi

echo "rghw-portforward: localhost:${LOCAL_PORT} -> ${SVC}:${CONTAINER_PORT} (${NAMESPACE})"
exec kubectl port-forward -n "$NAMESPACE" "svc/${SVC}" "${LOCAL_PORT}:${CONTAINER_PORT}"
