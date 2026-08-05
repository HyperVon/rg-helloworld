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
    echo "Building and deploying orchestrator + glyph catalog"
    bash "$PROJECT_ROOT/scripts/build-images.sh" || exit 1
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone4/orchestrator.yaml"
    retry kubectl apply -f "$PROJECT_ROOT/infra/k8s/milestone4/glyph-catalog.yaml"
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=run-orchestrator --timeout=180s
    retry kubectl wait --for=condition=ready pod -n $NAMESPACE -l app=glyph-catalog --timeout=180s

    kubectl port-forward -n $NAMESPACE svc/run-orchestrator 8080:8080 &>/dev/null &
    PORTFORWARD_PIDS+=($!)
    sleep 3

    if ! command -v go >/dev/null 2>&1; then
        echo "SKIP: go not installed, skipping rghello run acceptance"
    else
        RESULT=$(cd "$PROJECT_ROOT/cmd/rghello" && go run . run --api-url "http://localhost:8080" --quiet --timeout 90s 2>/dev/null || true)
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

echo "=== All smoke tests passed! ==="
