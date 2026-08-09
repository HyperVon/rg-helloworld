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

diagnose_app_failure() {
    local app="$1"
    local timeout="$2"
    echo "--- diagnostics for app=$app (timeout ${timeout}s) ---"
    echo ">> pods:"
    kubectl get pods -n "$NAMESPACE" -l "app=$app" -o wide 2>&1 || true
    echo ">> describe:"
    kubectl describe pod -n "$NAMESPACE" -l "app=$app" 2>&1 | tail -n 120 || true
    echo ">> logs (last 100 lines):"
    kubectl logs -n "$NAMESPACE" -l "app=$app" --tail=100 2>&1 | head -n 120 || true
    echo ">> previous logs (if crashed):"
    kubectl logs -n "$NAMESPACE" -l "app=$app" --previous --tail=100 2>&1 | head -n 80 || true
    echo ">> events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' 2>&1 | grep -i "$app" | tail -n 20 || true
    echo ">> image pull check:"
    kubectl get pod -n "$NAMESPACE" -l "app=$app" -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].state.waiting.reason} {.status.containerStatuses[0].image} {"\n"}{end}' 2>&1 || true
    echo ">> resource pressure hints:"
    echo "   kubectl describe nodes | grep -A5 'Allocated resources'  # check Pending due to memory"
    echo "   docker ps | grep rghello-registry                       # check registry up"
    echo "   make images                                              # rebuild if ImagePullBackOff"
    echo "   bash scripts/collect-diagnostics.sh                      # full dump to .local/diagnostics/"
    echo "--- end diagnostics for $app ---"
}

wait_for_app_ready() {
    local app="$1"
    local timeout="${2:-300}"
    local elapsed=0
    local last_phase=""
    while [[ $elapsed -lt $timeout ]]; do
        local ready="false"
        if kubectl get pod -n "$NAMESPACE" -l "app=$app" \
            --field-selector=status.phase=Running \
            -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' \
            2>/dev/null | grep -q '^true$'; then
            ready="true"
        fi
        if [[ "$ready" == "true" ]]; then
            echo "pod/app=$app condition met (${elapsed}s)"
            return 0
        fi
        if (( elapsed > 0 && elapsed % 30 == 0 )); then
            local phase
            phase=$(kubectl get pod -n "$NAMESPACE" -l "app=$app" \
                --field-selector=status.phase=Running \
                -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")
            local waiting
            waiting=$(kubectl get pod -n "$NAMESPACE" -l "app=$app" \
                --field-selector=status.phase=Running \
                -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo "")
            if [[ -n "$waiting" ]]; then
                echo "  pod/app=$app phase=$phase waiting=$waiting elapsed=${elapsed}s..."
            elif [[ "$phase" != "$last_phase" ]]; then
                echo "  pod/app=$app phase=$phase elapsed=${elapsed}s..."
            fi
            last_phase="$phase"
        fi
        sleep 5
        ((elapsed += 5))
    done
    echo "ERROR: pod/app=$app not ready after ${timeout}s"
    diagnose_app_failure "$app" "$timeout"
    return 1
}

restart_application_deployments() {
    local app
    local timeout
    local applications=(
        glyph-catalog
        geometry-engine
        run-orchestrator
        vector-normalizer
        rasterizer
        image-pipeline
        ocr-worker
        adjudicator
        phrase-assembler
        event-gateway
        telemetry-element
        artifact-inspector
        web-shell
    )

    echo "Restarting application deployments to pull rebuilt image tags..."
    for app in "${applications[@]}"; do
        if ! kubectl get deployment "$app" -n "$NAMESPACE" >/dev/null 2>&1; then
            continue
        fi
        retry kubectl rollout restart "deployment/$app" -n "$NAMESPACE"
        timeout=180
        if [[ "$app" == "run-orchestrator" || "$app" == "glyph-catalog" ]]; then
            timeout=360
        fi
        retry kubectl rollout status "deployment/$app" -n "$NAMESPACE" --timeout="${timeout}s"
    done
}

echo "=== Deploying Rube Goldberg services ==="

# DiskPressure pre-flight: reclaim host docker layers + remove Failed/Evicted pods before scheduling
if kubectl describe node k3d-rube-goldberg-server-0 2>/dev/null | grep -q "DiskPressure.*True"; then
    echo "DiskPressure detected — reclaiming host storage and clearing Failed pods..."
    docker image prune -af --filter "until=24h" 2>&1 | tail -n 5 || true
    kubectl delete pod -n "$NAMESPACE" --field-selector=status.phase=Failed 2>&1 | tail -n 5 || true
    # Evicted pods have status.phase=Failed but some stay Pending; delete by reason as well
    for p in $(kubectl get pods -n "$NAMESPACE" 2>&1 | awk '/Evicted/{print $1}'); do kubectl delete pod -n "$NAMESPACE" "$p" 2>&1 | tail -n 1 || true; done
    echo "If DiskPressure persists, run: docker restart k3d-rube-goldberg-server-0 && sleep 30 && kubectl wait --for=condition=Ready node k3d-rube-goldberg-server-0 --timeout=60s"
fi

# Milestone 5 base (catalog + geometry only — orchestrator/vector are milestone6; milestone5 tags are aliased in build-images.sh)
echo "Applying Milestone 5 manifests"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/glyph-catalog.yaml"
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/geometry-engine.yaml"
# Keep milestone5 orchestrator/vector as best-effort fallback for old clusters; milestone6 will overlay
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/orchestrator.yaml" 2>&1 | grep -v "not found" || true
retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/vector-normalizer.yaml" 2>&1 | grep -v "not found" || true

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

echo "Checking infra dependencies (Kafka/Redis/Postgres/MinIO) if present..."
for infra in kafka-controller postgres-postgresql redis-master minio; do
    if kubectl get pods -n "$NAMESPACE" -l "app=$infra" --no-headers 2>/dev/null | grep -q .; then
        echo "  infra $infra exists, waiting 60s for at least one ready..."
        kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l "app=$infra" --timeout=60s 2>&1 || echo "  warn: $infra not Ready yet (may still be starting)"
    fi
    # also check helm-generated labels
    if kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$infra" --no-headers 2>/dev/null | grep -q .; then
        kubectl wait --for=condition=Ready pod -n "$NAMESPACE" -l "app.kubernetes.io/name=$infra" --timeout=60s 2>&1 || true
    fi
done

restart_application_deployments

echo "Waiting for core app deployments to be ready..."
# JVM services need longer budget (startupProbe up to 300s), others stay at 180s
FAILED_APPS=()
wait_for_app_ready run-orchestrator 360 || FAILED_APPS+=("run-orchestrator")
wait_for_app_ready glyph-catalog 360 || FAILED_APPS+=("glyph-catalog")
wait_for_app_ready geometry-engine 180 || FAILED_APPS+=("geometry-engine")
wait_for_app_ready vector-normalizer 180 || FAILED_APPS+=("vector-normalizer")
wait_for_app_ready rasterizer 180 || FAILED_APPS+=("rasterizer")
wait_for_app_ready image-pipeline 180 || FAILED_APPS+=("image-pipeline")
wait_for_app_ready ocr-worker 180 || FAILED_APPS+=("ocr-worker")
wait_for_app_ready adjudicator 180 || FAILED_APPS+=("adjudicator")
wait_for_app_ready phrase-assembler 180 || FAILED_APPS+=("phrase-assembler")
wait_for_app_ready event-gateway 180 || FAILED_APPS+=("event-gateway")
wait_for_app_ready telemetry-element 180 || FAILED_APPS+=("telemetry-element")
wait_for_app_ready artifact-inspector 180 || FAILED_APPS+=("artifact-inspector")

# Also check rollout status with extended timeout for JVM
retry kubectl rollout status deployment/run-orchestrator -n "$NAMESPACE" --timeout=300s || FAILED_APPS+=("run-orchestrator-rollout")
retry kubectl rollout status deployment/glyph-catalog -n "$NAMESPACE" --timeout=300s || FAILED_APPS+=("glyph-catalog-rollout")
retry kubectl rollout status deployment/vector-normalizer -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/rasterizer -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/image-pipeline -n "$NAMESPACE" --timeout=180s || true
retry kubectl rollout status deployment/phrase-assembler -n "$NAMESPACE" --timeout=180s || true

echo "Deploy complete. Current pods:"
kubectl get pods -n "$NAMESPACE" || true
echo ""
if [[ ${#FAILED_APPS[@]} -gt 0 ]]; then
    echo "WARNING: some apps not ready: ${FAILED_APPS[*]}"
    echo "--- Summary diagnostics ---"
    kubectl get pods -n "$NAMESPACE" -o wide || true
    echo "--- Recent events ---"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -n 30 || true
    echo ""
    echo "Remediation hints:"
    echo "  # ImagePullBackOff -> rebuild:"
    echo "  make images && kubectl rollout restart deployment/${FAILED_APPS[0]} -n $NAMESPACE"
    echo "  # Pending/OOMKilled -> free memory:"
    echo "  docker image prune -af; kubectl delete pod -n $NAMESPACE --field-selector=status.phase=Failed"
    echo "  bash scripts/low-memory-profile.sh; kubectl rollout restart deployment -n $NAMESPACE --all"
    echo "  # Crashing -> check logs:"
    echo "  kubectl logs -n $NAMESPACE -l app=${FAILED_APPS[0]} --previous --tail=100"
    echo "  bash scripts/collect-diagnostics.sh  # -> .local/diagnostics/"
else
    echo "All core apps reported Ready."
fi
