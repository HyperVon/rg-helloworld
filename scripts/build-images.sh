#!/usr/bin/env bash
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
    local context="${4:-${PROJECT_ROOT}}"
    docker build -f "${PROJECT_ROOT}/${dockerfile}" -t "${REGISTRY}/${name}:${tag}" "${context}"
    docker push "${REGISTRY}/${name}:${tag}"
}
 
build_and_push glyph-catalog services/glyph-catalog-java/Dockerfile milestone5
build_and_push geometry-engine services/geometry-engine-cpp/Dockerfile milestone5
 
build_and_push run-orchestrator services/run-orchestrator-kotlin/Dockerfile milestone6
# Alias milestone5 tag for backward-compat: deploy.sh/smoke-test.sh apply milestone5 manifests before overlaying milestone6
docker tag "${REGISTRY}/run-orchestrator:milestone6" "${REGISTRY}/run-orchestrator:milestone5"
docker push "${REGISTRY}/run-orchestrator:milestone5"
build_and_push vector-normalizer services/vector-normalizer-go/Dockerfile milestone6
docker tag "${REGISTRY}/vector-normalizer:milestone6" "${REGISTRY}/vector-normalizer:milestone5"
docker push "${REGISTRY}/vector-normalizer:milestone5"
build_and_push rasterizer services/rasterizer-dotnet/Dockerfile milestone6
build_and_push image-pipeline services/image-pipeline-python/Dockerfile milestone7 services/image-pipeline-python
build_and_push ocr-worker services/ocr-worker-node/Dockerfile milestone8 services/ocr-worker-node
build_and_push adjudicator services/adjudicator-ruby/Dockerfile milestone8 services/adjudicator-ruby
build_and_push phrase-assembler services/phrase-assembler-rust/Dockerfile milestone9 services/phrase-assembler-rust
build_and_push event-gateway services/event-gateway-node/Dockerfile milestone11 services/event-gateway-node
build_and_push telemetry-element services/telemetry-element/Dockerfile milestone11 services/telemetry-element
build_and_push artifact-inspector services/artifact-inspector-ruby/Dockerfile milestone11 services/artifact-inspector-ruby
build_and_push web-shell services/web-shell/Dockerfile milestone11 services/web-shell

echo ">> Images pushed to ${REGISTRY} (milestone5 + milestone6 + milestone7 + milestone8 + milestone9 + milestone10 + milestone11)"
