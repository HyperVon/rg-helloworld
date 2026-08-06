#!/usr/bin/env bash
set -euo pipefail

# Delete k3d cluster
echo "Deleting k3d cluster 'rube-goldberg'..."
k3d cluster delete rube-goldberg

echo "K3s cluster deleted successfully."
