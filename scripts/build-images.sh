# Build and push Milestone 5 container images to the k3d local registry.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="localhost:5001"
TAG="milestone5"

build_and_push() {
    local name="$1"
    local dockerfile="$2"
    echo ">> Building ${name} image (${REGISTRY}/${name}:${TAG})"
    docker build -f "${PROJECT_ROOT}/${dockerfile}" -t "${REGISTRY}/${name}:${TAG}" "${PROJECT_ROOT}"
    docker push "${REGISTRY}/${name}:${TAG}"
}

build_and_push run-orchestrator services/run-orchestrator-kotlin/Dockerfile
build_and_push glyph-catalog services/glyph-catalog-java/Dockerfile
build_and_push geometry-engine services/geometry-engine-cpp/Dockerfile
build_and_push vector-normalizer services/vector-normalizer-go/Dockerfile

echo ">> Images pushed to ${REGISTRY} (${TAG})"
