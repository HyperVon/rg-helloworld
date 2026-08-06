#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="rube-goldberg"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

POSTGRES_USER="postgres"
POSTGRES_PASSWORD="PostgresPassw0rd!"
POSTGRES_DB="postgres"
REDIS_PASSWORD="RedisPassw0rd!"
MINIO_ROOT_USER="minioadmin"
MINIO_ROOT_PASSWORD="minioadmin"
MINIO_BUCKET="rube-goldberg-artifacts"

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

cleanup_portforward() {
    for pid in "${PORTFORWARD_PIDS[@]:-}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap cleanup_portforward EXIT
PORTFORWARD_PIDS=()

echo "=== Platform Smoke Tests ==="

# Wait for pods to be ready
retry kubectl wait --for=condition=ready pod --all -n $NAMESPACE --timeout=300s

echo ""
echo "--- Test 1: Kafka produce + consume ---"
TOPIC="rg.smoke-test.v1"

KAFKA_BROKER="kafka-controller-0.kafka-controller-headless.$NAMESPACE.svc.cluster.local:9092"

# Create topic from inside the cluster
echo "Creating topic $TOPIC"
retry kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
    kafka-topics.sh --create --topic $TOPIC --bootstrap-server $KAFKA_BROKER --partitions 1 --replication-factor 1 --if-not-exists

# Produce a message
TEST_MESSAGE="Hello World from Kafka"
echo "Producing message: $TEST_MESSAGE"
retry kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
    bash -c "echo '$TEST_MESSAGE' | kafka-console-producer.sh --topic $TOPIC --bootstrap-server $KAFKA_BROKER"

# Consume the message
echo "Consuming message..."
CONSUMED=$(retry kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
    timeout 15 kafka-console-consumer.sh --topic $TOPIC --bootstrap-server $KAFKA_BROKER --from-beginning --max-messages 1 2>/dev/null | tail -1)

if [[ "$CONSUMED" == "$TEST_MESSAGE" ]]; then
    echo "PASS: Kafka message round-tripped correctly"
else
    echo "FAIL: Kafka test - expected '$TEST_MESSAGE', got '$CONSUMED'"
    exit 1
fi
echo ""

# --- Test 2: MinIO artifact round trip ---
echo "--- Test 2: MinIO artifact round trip ---"
TEST_FILE="/tmp/rghello-test-artifact.txt"
echo "Hello World from MinIO" > "$TEST_FILE"
ORIGINAL_HASH=$(sha256sum "$TEST_FILE" | awk '{print $1}')

kubectl port-forward -n $NAMESPACE svc/minio 9000:9000 &>/dev/null &
PORTFORWARD_PIDS+=($!)
sleep 3

mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD --quiet
mc mb local/$MINIO_BUCKET --ignore-existing --quiet 2>&1 || true
mc cp "$TEST_FILE" local/$MINIO_BUCKET/test-artifact.txt --quiet
DOWNLOAD_FILE="/tmp/rghello-test-artifact-downloaded.txt"
mc cp local/$MINIO_BUCKET/test-artifact.txt "$DOWNLOAD_FILE" --quiet
DOWNLOADED_HASH=$(sha256sum "$DOWNLOAD_FILE" | awk '{print $1}')

kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
PORTFORWARD_PIDS=()
mc alias rm local 2>/dev/null || true

if [[ "$DOWNLOADED_HASH" == "$ORIGINAL_HASH" ]]; then
    echo "PASS: MinIO artifact round-tripped with matching hash ($ORIGINAL_HASH)"
else
    echo "FAIL: MinIO hash mismatch - expected $ORIGINAL_HASH, got $DOWNLOADED_HASH"
    exit 1
fi
echo ""

# --- Test 3: PostgreSQL connectivity ---
echo "--- Test 3: PostgreSQL connectivity ---"
kubectl port-forward -n $NAMESPACE svc/postgres-postgresql 5432:5432 &>/dev/null &
PORTFORWARD_PIDS+=($!)
sleep 3

export PGPASSWORD="$POSTGRES_PASSWORD"
retry psql -h localhost -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT 'PostgreSQL connection OK' as result;"

echo "PASS: PostgreSQL is accepting connections"
kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
PORTFORWARD_PIDS=()
echo ""

# --- Test 4: Redis connectivity ---
echo "--- Test 4: Redis connectivity ---"
kubectl port-forward -n $NAMESPACE svc/redis-master 6379:6379 &>/dev/null &
PORTFORWARD_PIDS+=($!)
sleep 3

RESPONSE=$(retry redis-cli -h localhost -p 6379 -a "$REDIS_PASSWORD" PING 2>/dev/null)
if [[ "$RESPONSE" == "PONG" ]]; then
    echo "PASS: Redis responded with PONG"
else
    echo "FAIL: Redis response: $RESPONSE"
    exit 1
fi
kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
PORTFORWARD_PIDS=()
echo ""

# --- Test 5: Milestone 4 SOAP planning + vertical slice (CLI -> REST -> SOAP -> Kafka -> SSE) ---
echo "--- Test 5: Milestone 4 SOAP planning + vertical slice ---"

if command -v docker >/dev/null 2>&1; then
    echo "Building and deploying orchestrator, glyph catalog, and Milestone 5 workers"
    bash "$PROJECT_ROOT/scripts/build-images.sh" || exit 1
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/orchestrator.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/glyph-catalog.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/geometry-engine.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone5/vector-normalizer.yaml"
    echo "Deploying Milestone 6 overlays (rasterizer + updated workers)"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/run-orchestrator.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/vector-normalizer.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone6/rasterizer.yaml"
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=run-orchestrator --timeout=180s
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=glyph-catalog --timeout=180s
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=geometry-engine --timeout=180s
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=vector-normalizer --timeout=180s
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=rasterizer --timeout=180s
    retry kubectl rollout status deployment/run-orchestrator -n $NAMESPACE --timeout=180s
    retry kubectl rollout status deployment/vector-normalizer -n $NAMESPACE --timeout=180s
    retry kubectl rollout status deployment/rasterizer -n $NAMESPACE --timeout=180s

    kubectl port-forward -n $NAMESPACE svc/run-orchestrator 8080:8080 &>/dev/null &
    PORTFORWARD_PIDS+=($!)
    sleep 3

    if ! command -v go >/dev/null 2>&1; then
        echo "SKIP: go not installed, skipping rghello run acceptance"
    else
        if ! RESULT=$(cd "$PROJECT_ROOT/cmd/rghello" && go run . run --api-url "http://localhost:8080" --quiet --timeout 90s 2>/dev/null); then
            RESULT=""
        fi
        if [[ "$RESULT" == "Hello World" ]]; then
            echo "PASS: rghello run printed 'Hello World'"
        else
            echo "FAIL: rghello run printed '$RESULT'"
            kubectl logs -n $NAMESPACE deploy/run-orchestrator --tail=20 || true
            kubectl logs -n $NAMESPACE deploy/glyph-catalog --tail=20 || true
            exit 1
        fi
    fi

    echo "Verifying glyph blueprints on rg.glyph-blueprints.v1"
    BLUEPRINTS=$(kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
        timeout 20 kafka-console-consumer.sh --topic rg.glyph-blueprints.v1 \
        --bootstrap-server $KAFKA_BROKER --from-beginning --max-messages 50 --timeout-ms 5000 2>/dev/null \
        | grep '"glyphInstanceId"' | tail -11 || true)
    BLUEPRINT_COUNT=$(printf '%s\n' "$BLUEPRINTS" | grep -c '"glyphInstanceId"')
    if [[ "$BLUEPRINT_COUNT" -eq 11 ]]; then
        echo "PASS: eleven ordered blueprint records observed"
    else
        echo "FAIL: expected 11 blueprint records, saw $BLUEPRINT_COUNT"
        exit 1
    fi
    for POSITION in 0 1 2 3 4 5 6 7 8 9 10; do
        if printf '%s\n' "$BLUEPRINTS" | grep -q "\"position\":$POSITION,"; then
            :
        else
            echo "FAIL: missing blueprint record at position $POSITION"
            exit 1
        fi
    done
    if printf '%s\n' "$BLUEPRINTS" | grep -q '"position":5,.*"kind":"GAP"'; then
        echo "PASS: gap position exists"
    else
        echo "FAIL: no gap blueprint at position 5"
        exit 1
    fi
    if printf '%s\n' "$BLUEPRINTS" | grep -qE '"(message|targetText|expectedCharacter|unicodeCodePoint|characterName|glyphLabel)"'; then
        echo "FAIL: blueprint events contain prohibited fields"
        exit 1
    else
        echo "PASS: blueprint events exclude plaintext and code points"
    fi

    if [[ ${#PORTFORWARD_PIDS[@]} -gt 0 ]]; then
        kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
        PORTFORWARD_PIDS=()
    fi
else
    echo "SKIP: docker not installed, skipping Milestone 4 vertical slice"
fi
echo ""

# --- Test 6: Milestone 5 geometry + vector artifacts ---
echo "--- Test 6: Milestone 5 geometry + vector artifacts ---"

if command -v docker >/dev/null 2>&1; then
    echo "Verifying geometry records on rg.geometry-expanded.v1"
    GEOMETRY=$(kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
        timeout 20 kafka-console-consumer.sh --topic rg.geometry-expanded.v1 \
        --bootstrap-server $KAFKA_BROKER --from-beginning --max-messages 50 --timeout-ms 5000 2>/dev/null \
        | grep '"glyphInstanceId"' | tail -11 || true)
    GEOMETRY_COUNT=$(printf '%s\n' "$GEOMETRY" | grep -c '"glyphInstanceId"')
    if [[ "$GEOMETRY_COUNT" -eq 11 ]]; then
        echo "PASS: eleven geometry-expanded records observed"
    else
        echo "FAIL: expected 11 geometry records, saw $GEOMETRY_COUNT"
        exit 1
    fi
    for POSITION in 0 1 2 3 4 5 6 7 8 9 10; do
        printf '%s\n' "$GEOMETRY" | grep -q "\"position\":$POSITION," || {
            echo "FAIL: missing geometry record at position $POSITION"
            exit 1
        }
    done
    if printf '%s\n' "$GEOMETRY" | grep -q '"kind":"GAP_GEOMETRY"'; then
        echo "PASS: gap geometry record exists"
    else
        echo "FAIL: no gap geometry record"
        exit 1
    fi
    if printf '%s\n' "$GEOMETRY" | grep -qE '"inputMaturity":10,.*"outputMaturity":20'; then
        echo "PASS: geometry records mature 10 -> 20"
    else
        echo "FAIL: geometry maturity not 10 -> 20"
        exit 1
    fi
    if printf '%s\n' "$GEOMETRY" | grep -qE '"(message|targetText|expectedCharacter|unicodeCodePoint|characterName|glyphLabel)"'; then
        echo "FAIL: geometry events contain prohibited fields"
        exit 1
    else
        echo "PASS: geometry events exclude plaintext and code points"
    fi

    echo "Verifying normalized records on rg.glyph-normalized.v1"
    NORMALIZED=$(kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
        timeout 20 kafka-console-consumer.sh --topic rg.glyph-normalized.v1 \
        --bootstrap-server $KAFKA_BROKER --from-beginning --max-messages 50 --timeout-ms 5000 2>/dev/null \
        | grep '"glyphInstanceId"' | tail -11 || true)
    NORMALIZED_COUNT=$(printf '%s\n' "$NORMALIZED" | grep -c '"glyphInstanceId"')
    if [[ "$NORMALIZED_COUNT" -eq 11 ]]; then
        echo "PASS: eleven glyph-normalized records observed"
    else
        echo "FAIL: expected 11 normalized records, saw $NORMALIZED_COUNT"
        exit 1
    fi
    for POSITION in 0 1 2 3 4 5 6 7 8 9 10; do
        printf '%s\n' "$NORMALIZED" | grep -q "\"position\":$POSITION," || {
            echo "FAIL: missing normalized record at position $POSITION"
            exit 1
        }
    done
    if printf '%s\n' "$NORMALIZED" | grep -qE '"inputMaturity":20,.*"outputMaturity":30'; then
        echo "PASS: normalized records mature 20 -> 30"
    else
        echo "FAIL: normalized maturity not 20 -> 30"
        exit 1
    fi
    if printf '%s\n' "$NORMALIZED" | grep -qE '"(message|targetText|expectedCharacter|unicodeCodePoint|characterName|glyphLabel)"'; then
        echo "FAIL: normalized events contain prohibited fields"
        exit 1
    else
        echo "PASS: normalized events exclude plaintext and code points"
    fi

    echo "Verifying MinIO artifacts"
    kubectl port-forward -n $NAMESPACE svc/minio 9000:9000 &>/dev/null &
    PORTFORWARD_PIDS+=($!)
    sleep 3
    mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD --quiet

    GEOMETRY_FILES=$(mc find local/$MINIO_BUCKET --name 'geometry-attempt-*.json' 2>/dev/null | wc -l | tr -d ' ')
    NORMALIZED_FILES=$(mc find local/$MINIO_BUCKET --name 'normalized-attempt-*.json' 2>/dev/null | wc -l | tr -d ' ')
    SVG_FILES=$(mc find local/$MINIO_BUCKET --name '*.svg' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$GEOMETRY_FILES" -ge 11 ]]; then
        echo "PASS: $GEOMETRY_FILES geometry artifacts in MinIO"
    else
        echo "FAIL: expected >= 11 geometry artifacts, saw $GEOMETRY_FILES"
        exit 1
    fi
    if [[ "$NORMALIZED_FILES" -ge 11 ]]; then
        echo "PASS: $NORMALIZED_FILES normalized artifacts in MinIO"
    else
        echo "FAIL: expected >= 11 normalized artifacts, saw $NORMALIZED_FILES"
        exit 1
    fi
    if [[ "$SVG_FILES" -ge 11 ]]; then
        echo "PASS: $SVG_FILES SVG artifacts in MinIO"
    else
        echo "FAIL: expected >= 11 SVG artifacts, saw $SVG_FILES"
        exit 1
    fi

    printf '%s\n' "$NORMALIZED" > /tmp/rghello-normalized-records.txt
    if python3 - "$MINIO_BUCKET" /tmp/rghello-normalized-records.txt <<'PYEOF'
import hashlib
import json
import subprocess
import sys

bucket, records_file = sys.argv[1], sys.argv[2]
bad = 0
checked = 0
with open(records_file, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        event = json.loads(line)
        data = event["data"]
        svg_keys = [a for a in data.get("outputArtifacts", []) if a.endswith(".svg")]
        if not svg_keys:
            continue
        svg_key = svg_keys[0]
        expected = data["svgSha256"]
        target = "/tmp/rghello-svg-check.svg"
        subprocess.run(
            ["mc", "cp", f"local/{bucket}/{svg_key}", target, "--quiet"],
            check=True,
            capture_output=True,
        )
        with open(target, "rb") as svg:
            content = svg.read()
        if b"<text" in content or b"<font" in content:
            print(f"FAIL: svg {svg_key} contains text elements")
            bad = 1
            break
        actual = hashlib.sha256(content).hexdigest()
        if actual != expected:
            print(f"FAIL: svg {svg_key} sha256 {actual} != event {expected}")
            bad = 1
            break
        checked += 1
print(f"checked {checked} SVG artifacts against their svgSha256")
sys.exit(bad)
PYEOF
    then
        echo "PASS: SVG artifacts contain no text elements and match their event sha256"
    else
        echo "FAIL: SVG artifact verification failed"
        exit 1
    fi
    rm -f /tmp/rghello-normalized-records.txt /tmp/rghello-svg-check.svg
    mc alias rm local 2>/dev/null || true

    if [[ ${#PORTFORWARD_PIDS[@]} -gt 0 ]]; then
        kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
        PORTFORWARD_PIDS=()
    fi
else
    echo "SKIP: docker not installed, skipping Milestone 5 artifact checks"
fi
echo ""

# --- Test 7: Milestone 6 gRPC rasterization ---
echo "--- Test 7: Milestone 6 gRPC rasterization ---"

if command -v docker >/dev/null 2>&1; then
    echo "Verifying rasterized records on rg.glyph-rasterized.v1"
    RASTERIZED=$(kubectl exec -n $NAMESPACE kafka-controller-0 -c kafka -- \
        timeout 20 kafka-console-consumer.sh --topic rg.glyph-rasterized.v1 \
        --bootstrap-server $KAFKA_BROKER --from-beginning --max-messages 200 --timeout-ms 5000 2>/dev/null \
        | grep '"glyphInstanceId"' || true)
    RASTER_RUNID=$(printf '%s\n' "$RASTERIZED" | tail -1 | grep -o '"runId":"[^"]*"' | cut -d'"' -f4)
    RASTERIZED=$(printf '%s\n' "$RASTERIZED" | grep "\"runId\":\"$RASTER_RUNID\"" || true)
    RASTERIZED_COUNT=$(printf '%s\n' "$RASTERIZED" | grep -c '"glyphInstanceId"')
    if [[ "$RASTERIZED_COUNT" -eq 10 ]]; then
        echo "PASS: ten glyph-rasterized records observed (gap excluded)"
    else
        echo "FAIL: expected 10 rasterized records, saw $RASTERIZED_COUNT"
        exit 1
    fi
    for POSITION in 0 1 2 3 4 6 7 8 9 10; do
        printf '%s\n' "$RASTERIZED" | grep -q "\"position\":$POSITION," || {
            echo "FAIL: missing rasterized record at position $POSITION"
            exit 1
        }
    done
    if printf '%s\n' "$RASTERIZED" | grep -q '"position":5,'; then
        echo "FAIL: rasterized record exists for the gap position"
        exit 1
    fi
    if printf '%s\n' "$RASTERIZED" | grep -qE '"inputMaturity":30,.*"outputMaturity":40'; then
        echo "PASS: rasterized records mature 30 -> 40"
    else
        echo "FAIL: rasterized maturity not 30 -> 40"
        exit 1
    fi
    if printf '%s\n' "$RASTERIZED" | grep -qE '"(message|targetText|expectedCharacter|unicodeCodePoint|characterName|glyphLabel)"'; then
        echo "FAIL: rasterized events contain prohibited fields"
        exit 1
    else
        echo "PASS: rasterized events exclude plaintext and code points"
    fi

    echo "Verifying raster PNG artifacts in MinIO"
    kubectl port-forward -n $NAMESPACE svc/minio 9000:9000 &>/dev/null &
    PORTFORWARD_PIDS+=($!)
    sleep 3
    mc alias set local http://localhost:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD --quiet

    RASTER_FILES=$(mc find local/$MINIO_BUCKET --name 'raster-attempt-*.png' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$RASTER_FILES" -ge 10 ]]; then
        echo "PASS: $RASTER_FILES raster PNG artifacts in MinIO"
    else
        echo "FAIL: expected >= 10 raster PNG artifacts, saw $RASTER_FILES"
        exit 1
    fi

    printf '%s\n' "$RASTERIZED" > /tmp/rghello-rasterized-records.txt
    if python3 - "$MINIO_BUCKET" /tmp/rghello-rasterized-records.txt <<'PYEOF'
import hashlib
import json
import subprocess
import sys

bucket, records_file = sys.argv[1], sys.argv[2]
bad = 0
checked = 0
with open(records_file, encoding="utf-8") as handle:
    for line in handle:
        line = line.strip()
        if not line:
            continue
        event = json.loads(line)
        data = event["data"]
        raster = data["raster"]
        target = "/tmp/rghello-raster-check.png"
        subprocess.run(
            ["mc", "cp", f"local/{bucket}/{raster['objectKey']}", target, "--quiet"],
            check=True,
            capture_output=True,
        )
        with open(target, "rb") as png:
            content = png.read()
        if not content.startswith(b"\x89PNG\r\n\x1a\n"):
            print(f"FAIL: {raster['objectKey']} is not a PNG")
            bad = 1
            break
        actual = hashlib.sha256(content).hexdigest()
        if actual != raster["sha256"]:
            print(f"FAIL: raster {raster['objectKey']} sha256 {actual} != event {raster['sha256']}")
            bad = 1
            break
        if raster["contentType"] != "image/png" or raster["width"] < 1 or raster["height"] < 1:
            print(f"FAIL: raster metadata wrong for {raster['objectKey']}: {raster}")
            bad = 1
            break
        checked += 1
print(f"checked {checked} raster PNG artifacts against their event sha256")
sys.exit(bad)
PYEOF
    then
        echo "PASS: raster PNGs are valid, non-empty, and match their event sha256"
    else
        echo "FAIL: raster PNG artifact verification failed"
        exit 1
    fi
    rm -f /tmp/rghello-rasterized-records.txt /tmp/rghello-raster-check.png
    mc alias rm local 2>/dev/null || true

    if [[ ${#PORTFORWARD_PIDS[@]} -gt 0 ]]; then
        kill "${PORTFORWARD_PIDS[0]}" 2>/dev/null || true
        PORTFORWARD_PIDS=()
    fi
else
    echo "SKIP: docker not installed, skipping Milestone 6 rasterization checks"
fi
echo ""
 
# --- Test 8: Milestone 7 Composition and preprocessing ---
echo "--- Test 8: Milestone 7 composition and preprocessing ---"
if command -v python3 &>/dev/null && [ -d "${PROJECT_ROOT}/services/image-pipeline-python" ]; then
    cd "${PROJECT_ROOT}/services/image-pipeline-python"
    if PYTHONPATH=src python3 -m unittest discover -s tests -v 2>&1 | grep -q "OK"; then
        echo "PASS: image pipeline unit tests"
    else
        echo "FAIL: image pipeline unit tests"
        cd "${PROJECT_ROOT}"
        exit 1
    fi
    if PYTHONPATH=src python3 -m compileall -q src 2>&1; then
        echo "PASS: image pipeline compile check"
    else
        echo "FAIL: image pipeline compile check"
        cd "${PROJECT_ROOT}"
        exit 1
    fi
    cd "${PROJECT_ROOT}"
else
    echo "SKIP: python3 not found, skipping Milestone 7 checks"
fi
echo ""
 
echo "=== All smoke tests passed! ==="
