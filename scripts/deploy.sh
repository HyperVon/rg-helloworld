#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="rube-goldberg"

retry() {
    local n=1
    local max=5
    local delay=5
    while true; do
        if "$@"; then
            break
        fi
        if [[ $n -lt $max ]]; then
            ((n++))
            echo "Command failed. Attempt $n/$max:"
            sleep $delay
        else
            echo "Command failed after $max attempts."
            return 1
        fi
    done
}

wait_for_app_ready() {
    local app="$1"
    local timeout="${2:-180}"
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        local ready
        ready=$(kubectl get pod -n "$NAMESPACE" -l "app=$app" -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
        if [[ "$ready" == "true" ]]; then
            echo "pod/app=$app condition met"
            return 0
        fi
        sleep 2
        ((elapsed += 2))
    done
    echo "ERROR: pod/app=$app not ready after ${timeout}s"
    return 1
}

echo "=== Deploying Rube Goldberg services ==="

# Milestone 5 base (orchestrator + catalog + geometry + vector)
echo "Applying Milestone 5 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/orchestrator.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/glyph-catalog.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/geometry-engine.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/vector-normalizer.yaml"

# Milestone 6 overlays (updated orchestrator/vector + rasterizer)
echo "Applying Milestone 6 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/run-orchestrator.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/vector-normalizer.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/rasterizer.yaml"

# Milestone 7
echo "Applying Milestone 7 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone7/image-pipeline.yaml"

# Milestone 8
echo "Applying Milestone 8 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone8/ocr-worker.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone8/adjudicator.yaml"

# Milestone 9
echo "Applying Milestone 9 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone9/phrase-assembler.yaml"

# Milestone 10
echo "Applying Milestone 10 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone10/event-gateway.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone10/telemetry-element.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone10/artifact-inspector.yaml"
if [[ -f "$PROJECT_ROOT/infra/k8s/milestone10/web-shell.yaml" ]]; then
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone10/web-shell.yaml"
fi

# Apply any milestone 10 web-shell or other if present
for f in "$PROJECT_ROOT"/infra/k8s/milestone10/*.yaml; do
    # already applied known ones, but ensure any extra is applied idempotently
    retry kubectl apply -f "$f" >/dev/null 2>&1 || true
done

# Milestone 11 observability
echo "Ensuring Grafana credentials secret"
kubectl create secret generic grafana-credentials -n "$NAMESPACE" --from-literal=admin-password=admin --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 || true

echo "Applying Milestone 11 manifests"
for f in "$PROJECT_ROOT"/infra/k8s/milestone11/*.yaml; do
    retry kubectl apply -f "$f" || echo "warn: failed to apply $f"
done

echo "Waiting for core app deployments to be ready..."
wait_for_app_ready run-orchestrator 180 || true
wait_for_app_ready glyph-catalog 180 || true
wait_for_app_ready geometry-engine 180 || true
wait_for_app_ready vector-normalizer 180 || true
wait_for_app_ready rasterizer 180 || true
wait_for_app_ready image-pipeline 180 || true
wait_for_app_ready ocr-worker 180 || true
wait_for_app_ready adjudicator 180 || true
wait_for_app_ready phrase-assembler 180 || true
wait_for_app_ready event-gateway 180 || true
wait_for_app_ready telemetry-element 180 || true
wait_for_app_ready artifact-inspector 180 || true

retry kubectl rollout status deployment/run-orchestrator -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/vector-normalizer -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/rasterizer -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/image-pipeline -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/phrase-assembler -n "$NAMESPACE" --timeout=180s || true

echo "Deploy complete. Current pods:"
kubectl get pods -n "$NAMESPACE" || true
