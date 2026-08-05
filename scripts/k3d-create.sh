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
kubectl wait --for=condition=ready pod --all -A --timeout=180s

echo "Kubernetes cluster ready:"
kubectl cluster-info

echo ""
echo "Registry endpoint: localhost:5001"
echo "Registry has been created and configured for use with k3d"
echo ""
echo "To use the registry in your Kubernetes manifests, reference images as:"
echo "  localhost:5001/your-image:tag"
