# Build and push Milestone 4 container images to the k3d local registry.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="localhost:5001"
TAG="milestone4"

echo ">> Building orchestrator image (${REGISTRY}/run-orchestrator:${TAG})"
docker build -f "${PROJECT_ROOT}/services/run-orchestrator-kotlin/Dockerfile" -t "${REGISTRY}/run-orchestrator:${TAG}" "${PROJECT_ROOT}"
docker push "${REGISTRY}/run-orchestrator:${TAG}"

echo ">> Building glyph-catalog image (${REGISTRY}/glyph-catalog:${TAG})"
docker build -f "${PROJECT_ROOT}/services/glyph-catalog-java/Dockerfile" -t "${REGISTRY}/glyph-catalog:${TAG}" "${PROJECT_ROOT}"
docker push "${REGISTRY}/glyph-catalog:${TAG}"

echo ">> Images pushed to ${REGISTRY}"
