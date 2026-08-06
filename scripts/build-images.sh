# Build and push container images to the k3d local registry.
#
# Milestone 5 services (glyph-catalog, geometry-engine) are unchanged and
# keep their milestone5 tags; the services that gained Milestone 6 behavior
# (run-orchestrator, vector-normalizer) and the new rasterizer are tagged
# milestone6. The smoke test applies the milestone5 manifests first and the
# milestone6 manifests as overlays, so final cluster state is milestone6.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="localhost:5001"

build_and_push() {
    local name="$1"
    local dockerfile="$2"
    local tag="$3"
    echo ">> Building ${name} image (${REGISTRY}/${name}:${tag})"
    docker build -f "${PROJECT_ROOT}/${dockerfile}" -t "${REGISTRY}/${name}:${tag}" "${PROJECT_ROOT}"
    docker push "${REGISTRY}/${name}:${tag}"
}

build_and_push glyph-catalog services/glyph-catalog-java/Dockerfile milestone5
build_and_push geometry-engine services/geometry-engine-cpp/Dockerfile milestone5

build_and_push run-orchestrator services/run-orchestrator-kotlin/Dockerfile milestone6
build_and_push vector-normalizer services/vector-normalizer-go/Dockerfile milestone6
build_and_push rasterizer services/rasterizer-dotnet/Dockerfile milestone6

echo ">> Images pushed to ${REGISTRY} (milestone5 + milestone6)"
