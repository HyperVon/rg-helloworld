#!/usr/bin/env bash
# Shared platform-dependency pod selectors for the rube-goldberg stack.
#
# These match the Helm-generated labels the deployed charts actually use
# (Bitnami Kafka/Postgres/Redis, MinIO chart). Both the legacy `app=<name>`
# form and the Helm `app.kubernetes.io/name=<name>` form are covered so a
# caller can resolve a dependency pod regardless of install method.
#
# This is the single source of truth consumed by scripts/collect-diagnostics.sh
# and scripts/deploy.sh. Source it from any script that needs to reach
# Kafka / Postgres / Redis / MinIO.

# shellcheck disable=SC2034 # consumed by scripts that source this file
INFRA_SELECTORS=(
  kafka-controller
  postgres-postgresql
  redis-master
  minio
)

# resolve_infra_pod SELECTOR NS
# Echoes the first pod name matching SELECTOR (trying both label forms), or an
# empty string if none resolves.
resolve_infra_pod() {
  local sel="$1"
  local ns="$2"
  local pod
  pod=$(kubectl get pods -n "$ns" -l "app=$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$pod" ]; then
    pod=$(kubectl get pods -n "$ns" -l "app.kubernetes.io/name=$sel" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  fi
  printf '%s' "$pod"
}
