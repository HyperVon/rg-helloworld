#!/usr/bin/env bash
set -euo pipefail

# Wait for all pods to be ready in the rube-goldberg namespace
echo "Waiting for all pods to be ready in namespace 'rube-goldberg'..."
kubectl wait --for=condition=ready pod --all -n rube-goldberg --timeout=300s

echo "All pods are ready."
