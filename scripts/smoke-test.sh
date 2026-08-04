#!/usr/bin/env bash
set -euo pipefail

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
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Attempt $n/$max:"
                sleep $delay
            else
                echo "Command failed after $max attempts."
                return 1
            fi
        }
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

echo "=== All smoke tests passed! ==="
