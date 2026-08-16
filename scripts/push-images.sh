#!/usr/bin/env bash
# Push the locally-built rube-goldberg images to the k3d local registry.
# (Previously a Milestone-2 stub that always exited 1; now wired to push.)
# This only pushes images already built and tagged for REGISTRY; it does not
# build. Requires the local registry from `make cluster` (k3d registry at
# localhost:5001, exposed in-cluster as rghello-registry:5001).
set -euo pipefail

REGISTRY="${RG_REGISTRY:-localhost:5001}"

# name:tag pairs mirror scripts/build-images.sh (no rebuild here).
IMAGES=(
  "glyph-catalog:milestone5"
  "geometry-engine:milestone5"
  "run-orchestrator:milestone6"
  "run-orchestrator:milestone5"
  "vector-normalizer:milestone6"
  "vector-normalizer:milestone5"
  "rasterizer:milestone6"
  "image-pipeline:milestone7"
  "ocr-worker:milestone8"
  "adjudicator:milestone8"
  "phrase-assembler:milestone9"
  "event-gateway:milestone11"
  "telemetry-element:milestone11"
  "artifact-inspector:milestone11"
  "web-shell:milestone11"
)

registry_reachable() {
  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "rghello-registry"; then
    return 0
  fi
  (exec 3<>"/dev/tcp/localhost/5001") 2>/dev/null
}

if ! registry_reachable; then
  echo "push-images.sh: local registry not reachable at ${REGISTRY} (run 'make cluster' first)."
  exit 1
fi

failed=0
for img in "${IMAGES[@]}"; do
  if ! docker image inspect "${REGISTRY}/${img}" >/dev/null 2>&1; then
    echo "skip: ${REGISTRY}/${img} not built locally"
    continue
  fi
  echo "pushing ${REGISTRY}/${img}"
  if ! docker push "${REGISTRY}/${img}"; then
    echo "ERROR: failed to push ${REGISTRY}/${img}"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "push-images.sh: $failed image(s) failed to push"
  exit 1
fi
echo "push-images.sh: done"
