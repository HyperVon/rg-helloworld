#!/usr/bin/env bash
# Collect diagnostics for the rube-goldberg stack.
set -euo pipefail

NS="rube-goldberg"
OUT=".local/diagnostics"
mkdir -p "$OUT"

say() { echo "[diagnostics] $*"; }

say "Collecting pod logs..."
kubectl get pods -n "$NS" -o wide > "$OUT/pods.txt" 2>&1 || true
for pod in $(kubectl get pods -n "$NS" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  kubectl logs -n "$NS" pod/"$pod" --tail=100 > "$OUT/${pod}.log" 2>&1 || true
done

say "Collecting events..."
kubectl get events -n "$NS" --sort-by='.lastTimestamp' > "$OUT/events.txt" 2>&1 || true

say "Collecting Kafka consumer groups..."
kafka_pod=$(kubectl get pods -n "$NS" -l app=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$kafka_pod" ]; then
  kubectl exec -n "$NS" "$kafka_pod" -- kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 --describe --all-groups 2>/dev/null > "$OUT/kafka-consumer-groups.txt" || true
fi

say "Collecting MinIO bucket inventory..."
minio_pod=$(kubectl get pods -n "$NS" -l app=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$minio_pod" ]; then
  kubectl exec -n "$NS" "$minio_pod" -- mc ls -r local/rube-goldberg-artifacts > "$OUT/minio-artifacts.txt" 2>&1 || true
fi

say "Collecting PostgreSQL connections..."
pg_pod=$(kubectl get pods -n "$NS" -l app=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$pg_pod" ]; then
  kubectl exec -n "$NS" "$pg_pod" -- psql -U postgres -c "SELECT * FROM pg_stat_activity;" > "$OUT/postgres-connections.txt" 2>&1 || true
fi

say "Collecting Redis info..."
redis_pod=$(kubectl get pods -n "$NS" -l app=redis -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$redis_pod" ]; then
  kubectl exec -n "$NS" "$redis_pod" -- redis-cli INFO > "$OUT/redis-info.txt" 2>&1 || true
fi

say "Diagnostics collected in $OUT"
