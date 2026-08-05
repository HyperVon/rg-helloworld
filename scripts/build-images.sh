#!/usr/bin/env bash
# Build and push Milestone 3 container images to the k3d local registry.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="localhost:5001"

echo ">> Building orchestrator image (${REGISTRY}/run-orchestrator:milestone3)"
docker build -t "${REGISTRY}/run-orchestrator:milestone3" "${PROJECT_ROOT}/services/run-orchestrator-kotlin"
docker push "${REGISTRY}/run-orchestrator:milestone3"

echo ">> Building temp-worker image (${REGISTRY}/temp-worker:milestone3)"
docker build -t "${REGISTRY}/temp-worker:milestone3" "${PROJECT_ROOT}/services/temp-worker-node"
docker push "${REGISTRY}/temp-worker:milestone3"

echo ">> Images pushed to ${REGISTRY}"
