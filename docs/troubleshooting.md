# Troubleshooting Guide

## Common failure modes

### 1. `rghw run` hangs with no output

**Symptoms:** CLI starts but never prints progress or final result.

**Causes:**
- Orchestrator SSE endpoint unreachable
- Kafka consumer lag causing delayed events
- Redis Streams backlog preventing snapshot delivery

**Remediation:**
```bash
# Check orchestrator health
curl -sf http://localhost:8080/healthz

# Check Kafka consumer lag
kubectl exec -n rube-goldberg <kafka-pod> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group run-orchestrator-v1

# Check Redis stream length
kubectl exec -n rube-goldberg deploy/redis -- redis-cli XLEN rg:run:<runId>:events
```

### 2. Pods stuck in Pending

**Symptoms:** `kubectl get pods` shows `Pending` status.

**Causes:**
- Ephemeral-storage capacity issues on k3d nodes
- Resource requests exceeding node capacity
- PVC binding failures

**Remediation:**
```bash
# Check node capacity
kubectl describe nodes | grep -A5 "Allocated resources"

# Check events
kubectl get events -n rube-goldberg --sort-by='.lastTimestamp'

# Quick fix: restart k3d cluster
make down
k3d cluster create rube-goldberg --config infra/k3d/cluster.yaml
```

### 3. Image pull failures

**Symptoms:** `ImagePullBackOff` or `ErrImagePull` status.

**Causes:**
- Local registry not running
- Image not built or pushed
- Network policy blocking registry access

**Remediation:**
```bash
# Check registry
kubectl get pods -n kube-system -l app=registry
docker ps | grep registry

# Rebuild and push
bash scripts/build-images.sh
```

### 4. Tesseract OCR failures

**Symptoms:** OCR worker reports `ENOENT` or `tesseract not found`.

**Causes:**
- Tesseract binary not installed in container
- Wrong `tesseract-ocr` package version
- Language data missing (`eng.traineddata`)

**Remediation:**
```bash
# Verify tesseract in pod
kubectl exec -n rube-goldberg deploy/ocr-worker -- tesseract --version

# Check language data
kubectl exec -n rube-goldberg deploy/ocr-worker -- ls /usr/share/tesseract-ocr/4.00/tessdata/
```

### 5. gRPC connection refused

**Symptoms:** Rasterizer or vector-normalizer cannot connect via gRPC.

**Causes:**
- Service not ready
- Port-forward not established
- Network policy blocking

**Remediation:**
```bash
# Check service endpoints
kubectl get endpoints -n rube-goldberg

# Port-forward if needed
kubectl port-forward -n rube-goldberg svc/rasterizer 50051:50051 &
```

### 6. Kafka consumer group rebalancing loops

**Symptoms:** High rebalance rate, no message consumption.

**Causes:**
- Too many concurrent consumers
- Session timeout too short
- Poll interval too long

**Remediation:**
```yaml
# Adjust consumer config in K8s manifest:
env:
  - name: KAFKA_SESSION_TIMEOUT_MS
    value: "30000"
  - name: KAFKA_MAX_POLL_INTERVAL_MS
    value: "300000"
```

### 7. Memory pressure / OOMKilled

**Symptoms:** Pod terminated with `OOMKilled` status.

**Causes:**
- Memory limit too low
- Memory leak in service
- Tesseract OCR consuming excessive memory

**Remediation:**
```bash
# Check pod events
kubectl describe pod -n rube-goldberg <pod-name> | grep -A10 "Last State"

# Increase memory limit in K8s manifest
# OCR worker: raise limit from 512Mi to 768Mi
# Image pipeline: raise limit from 1Gi to 2Gi
```

### 8. Protobuf / gRPC version mismatch

**Symptoms:** `rasterizer` returns `UNIMPLEMENTED` or `INVALID_ARGUMENT`.

**Causes:**
- Generated Go client out of sync with proto contract
- C# server using different proto version

**Remediation:**
```bash
# Regenerate Go client
bash scripts/gen-proto.sh

# Verify both sides use same proto version
grep "version" contracts/proto/rasterizer/v1/rasterizer.proto
```
