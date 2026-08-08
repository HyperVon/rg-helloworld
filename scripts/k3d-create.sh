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
    if ! k3d cluster create --config "$K3D_CONFIG" 2>&1; then
        # Transient host-port collision (e.g. 57242 already in use) -- clean and retry once with a new random port
        if k3d cluster list "$CLUSTER_NAME" >/dev/null 2>&1; then
            echo "Cluster create failed but cluster partially exists -- deleting for retry..."
            k3d cluster delete "$CLUSTER_NAME" >/dev/null 2>&1 || true
            sleep 2
        fi
        echo "Retrying k3d cluster create..."
        k3d cluster create --config "$K3D_CONFIG"
    fi
fi

# Verify cluster is ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready pod --all -n kube-system --timeout=180s || true
if ! kubectl wait --for=condition=Ready pod --all -n rube-goldberg --timeout=300s --field-selector=status.phase!=Succeeded 2>/dev/null; then
    echo "rube-goldberg: no pods yet (expected before 'make infra')"
fi
# don't fail on Completed jobs; the final gate is `make wait` which checks rube-goldberg properly

echo "Kubernetes cluster ready:"
kubectl cluster-info

echo ""
echo "Registry endpoint: localhost:5001"
echo "Registry has been created and configured for use with k3d"
echo ""
echo "To use the registry in your Kubernetes manifests, reference images as:"
echo "  localhost:5001/your-image:tag"
