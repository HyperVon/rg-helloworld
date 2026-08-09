#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="rube-goldberg"
TIMEOUT="${1:-600}"

echo "Waiting for all pods to be ready in namespace '$NAMESPACE' (timeout ${TIMEOUT}s)..."
# Ignore terminal pods left by completed jobs or replaced failed replicas.
if kubectl wait --for=condition=Ready pod --all -n "$NAMESPACE" --timeout="${TIMEOUT}s" \
    --field-selector=status.phase!=Succeeded,status.phase!=Failed 2>&1; then
    echo "All pods are ready."
    exit 0
fi

echo "WARNING: some pods not Ready after ${TIMEOUT}s"
echo "--- pods ---"
kubectl get pods -n "$NAMESPACE" -o wide || true
echo "--- events ---"
kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -n 30 || true
echo "--- not-ready pods detail ---"
for pod in $(kubectl get pods -n "$NAMESPACE" \
    --field-selector=status.phase!=Succeeded,status.phase!=Failed \
    -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==false)].metadata.name}' 2>/dev/null); do
    echo ">> $pod"
    kubectl describe pod -n "$NAMESPACE" "$pod" 2>&1 | tail -n 40 || true
    kubectl logs -n "$NAMESPACE" "$pod" --tail=30 2>&1 | head -n 40 || true
done
echo ""
echo "Hints:"
echo "  kubectl get pods -n $NAMESPACE -o wide                      # check ImagePullBackOff / Pending"
echo "  kubectl describe pod -n $NAMESPACE <pod> | grep -A5 Events   # reason"
echo "  kubectl logs -n $NAMESPACE <pod> --previous                 # crash"
echo "  docker ps | grep rghello-registry; make images               # registry / image"
echo "  bash scripts/low-memory-profile.sh                          # 4GiB laptop: patch to 256Mi"
echo "  bash scripts/collect-diagnostics.sh                          # dump to .local/diagnostics/"
exit 1
