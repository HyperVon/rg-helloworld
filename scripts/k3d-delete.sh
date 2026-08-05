#!/usr/bin/env bash
set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Delete k3d cluster
echo "Deleting k3d cluster 'rube-goldberg'..."
k3d cluster delete rube-goldberg

echo "K3s cluster deleted successfully."
