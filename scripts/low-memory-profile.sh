#!/usr/bin/env bash
# Apply low-memory resource profiles for constrained environments.
# This reduces memory requests/limits for all services to fit within
# a 4GiB total cluster memory budget.
set -euo pipefail

# shellcheck disable=SC2034 # ROOT is documented for future use
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="rube-goldberg"

say() { echo "[low-memory] $*"; }

apply_patch() {
  local manifest="$1"
  local name
  name=$(basename "$manifest" .yaml)
  say "Patching $name with low-memory profile"
  kubectl patch deployment "$name" -n "$NS" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources/limits/memory\", \"value\": \"256Mi\"}]" 2>/dev/null || true
  kubectl patch deployment "$name" -n "$NS" --type='json' -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/resources/requests/memory\", \"value\": \"64Mi\"}]" 2>/dev/null || true
}

say "Applying low-memory profile to all deployments..."
for deployment in $(kubectl get deployments -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  apply_patch "$deployment"
done

say "Low-memory profile applied. Verify with:"
say "  kubectl get deployments -n $NS -o wide"
