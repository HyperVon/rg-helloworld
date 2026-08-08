#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
K3D_CONFIG="$PROJECT_ROOT/infra/k3d/cluster.yaml"

CLUSTER_NAME="rube-goldberg"

# Create k3d cluster with local registry (idempotent: reuse an existing cluster)
if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
    echo "Cluster '$CLUSTER_NAME' already exists; reusing it."
else
    echo "Creating k3d cluster with local registry..."
    k3d cluster create --config "$K3D_CONFIG"
fi

# Verify cluster is ready
echo "Waiting for cluster to be ready..."
# Wait only for Running pods; Completed jobs (artifact-inspector/minio) are never Ready and would cause a timeout
kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=180s || true
kubectl wait --for=condition=Ready pod --all -n rube-goldberg --timeout=300s --field-selector=status.phase!=Succeeded || true
# don't fail on Completed jobs; the final gate is `make wait` which checks rube-goldberg properly

echo "Kubernetes cluster ready:"
kubectl cluster-info

echo ""
echo "Registry endpoint: localhost:5001"
echo "Registry has been created and configured for use with k3d"
echo ""
echo "To use the registry in your Kubernetes manifests, reference images as:"
echo "  localhost:5001/your-image:tag"
