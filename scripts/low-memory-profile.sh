#!/usr/bin/env bash
# Apply low-memory resource profiles for constrained environments.
# This reduces memory requests/limits for all services to fit within
# a 4GiB total cluster memory budget.
set -euo pipefail

# shellcheck disable=SC2034 # ROOT is documented for future use
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="rube-goldberg"

say() { echo "[low-memory] $*"; }

# Observability stack is sized by its own charts and must not be clobbered by
# the low-memory profile.
SKIP_DEPLOYMENTS="grafana prometheus loki tempo"

is_skipped() {
  local name="$1"
  local s
  for s in $SKIP_DEPLOYMENTS; do
    case "$name" in *"$s"*) return 0 ;; esac
  done
  return 1
}

apply_patch() {
  local name="$1"
  local cname
  cname=$(kubectl get deployment "$name" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].name}' 2>/dev/null)
  if [ -z "$cname" ]; then
    say "ERROR: cannot resolve container for $name"
    return 1
  fi
  say "Patching $name ($cname) with low-memory profile"
  if ! kubectl patch deployment "$name" -n "$NS" --type=strategic \
    -p="{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"$cname\",\"resources\":{\"limits\":{\"memory\":\"256Mi\"},\"requests\":{\"memory\":\"64Mi\"}}}]}}}}"; then
    say "ERROR: failed to patch $name"
    return 1
  fi
}

say "Applying low-memory profile to application deployments..."
failed=0
for deployment in $(kubectl get deployments -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  if is_skipped "$deployment"; then
    say "Skipping observability deployment $deployment"
    continue
  fi
  apply_patch "$deployment" || failed=1
done

if [ "$failed" -ne 0 ]; then
  say "ERROR: $failed deployment(s) failed to patch"
  exit 1
fi

say "Low-memory profile applied. Verify with:"
say "  kubectl get deployments -n $NS -o wide"
