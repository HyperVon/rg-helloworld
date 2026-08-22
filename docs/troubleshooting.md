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

### 8. Deploy waits `pod/app=run-orchestrator|glyph-catalog not ready after 180s`

**Symptoms:** `scripts/deploy.sh` prints `Waiting for core app deployments to be ready...` then `ERROR: pod/app=run-orchestrator not ready after 180s` / `pod/app=glyph-catalog not ready after 180s`. Earlier lines show `otel-collector`, `prometheus`, `tempo` `created` and `namespace/rube-goldberg configured` (harmless annotation warning). The deploy appears to hang for minutes.

**Causes:**

- JVM cold-start: Spring (glyph-catalog) and Ktor/Netty (orchestrator) need 30-80s; old manifests had `readinessProbe initialDelaySeconds: 5` with no `startupProbe`, so `livenessProbe` could restart the pod before it ever became Ready.
- `imagePullPolicy: Always` + registry DNS `rghello-registry:5001` vs `localhost:5001`: if `make images` didn't push, pod stays `ImagePullBackOff`/`ErrImagePull` for the whole wait.
- Infra not yet Ready: `run-orchestrator` probes `/healthz` only after Kafka `kafka:9092` and Redis `redis-master:6379` are reachable; Terraform Helm may still be starting them.
- Memory pressure on 4-8 GiB Colima: 12 app + 5 observability + Kafka/Redis/Postgres/MinIO exceeds node allocatable → `Pending`/`OOMKilled`.

**Remediation:**

```bash
# 1. See why the pod is not Ready (new deploy.sh prints this automatically)
kubectl get pods -n rube-goldberg -l app=run-orchestrator -o wide
kubectl get pods -n rube-goldberg -l app=glyph-catalog -o wide
kubectl describe pod -n rube-goldberg -l app=run-orchestrator | tail -n 80
kubectl logs -n rube-goldberg -l app=run-orchestrator --tail=100
kubectl logs -n rube-goldberg -l app=glyph-catalog --tail=100 --previous
kubectl get events -n rube-goldberg --sort-by='.lastTimestamp' | grep -E 'run-orchestrator|glyph-catalog|Failed'

# 2. Image pull?
kubectl get pod -n rube-goldberg -l app=run-orchestrator \
  -o jsonpath='{range .items[*]}{.metadata.name} {.status.containerStatuses[0].state.waiting.reason} {.status.containerStatuses[0].image} {"\n"}{end}'
docker ps | grep rghello-registry          # registry must be up
make images                                # rebuild + push to localhost:5001
kubectl rollout restart deployment/run-orchestrator deployment/glyph-catalog -n rube-goldberg

# 3. Infra still starting?
kubectl get pods -n rube-goldberg -l app=kafka -o wide
kubectl wait --for=condition=Ready pod -n rube-goldberg -l app=kafka --timeout=300s

# 4. Memory?
kubectl describe nodes | grep -A5 "Allocated resources"
kubectl top pods -n rube-goldberg 2>/dev/null || true
# 4 GiB laptop:
bash scripts/low-memory-profile.sh
kubectl rollout restart deployment -n rube-goldberg --all

# 5. Apply updated manifests (startupProbe 300s, increased deploy timeout 360s)
kubectl apply -f infra/k8s/milestone5/glyph-catalog.yaml
kubectl apply -f infra/k8s/milestone6/run-orchestrator.yaml
kubectl rollout status deployment/run-orchestrator -n rube-goldberg --timeout=300s
kubectl rollout status deployment/glyph-catalog -n rube-goldberg --timeout=300s

# 6. Full dump
bash scripts/collect-diagnostics.sh  # -> .local/diagnostics/
bash scripts/wait-ready.sh 600       # waits ignoring terminal Succeeded/Failed jobs, prints diagnostics
```

Fixed in `infra/k8s/milestone[456]/[glyph-catalog|run-orchestrator].yaml` via `startupProbe: failureThreshold 30 × period 10s = 300s` plus tuned `readinessProbe period 5s`, and in `scripts/deploy.sh` via `360s` timeout for JVM services, `300s` rollout timeout, 30s progress logs, automatic `diagnose_app_failure` + summary, and explicit application rollout restarts to pull rebuilt immutable image tags. `scripts/wait-ready.sh` excludes terminal `Succeeded` and `Failed` pods from readiness waits.

### 9. Protobuf / gRPC version mismatch

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

### 10. Ruby service CrashLoopBackOff with `Could not open library '...librdkafka.so'`

**Symptoms:** Adjudicator pods crash at boot (exit 1) while every other service rolls out green; logs show `Could not open library '/app/vendor/bundle/ruby/*/gems/rdkafka-*/ext/librdkafka.so'`, and `ldd` on that file inside the image reports `libsasl2.so.3: cannot open shared object` and/or `version 'GLIBC_2.xx' not found`. `make deploy` fails waiting for the rollout.

**Causes:**

- Host Ruby gems leaked into the image: the repo's `.bundle/config` sets
  `BUNDLE_PATH: vendor/bundle`, so a host-side `bundle install` populates
  `services/*/vendor/`; `COPY . /app/` swept that directory in because the
  services' `.dockerignore` did not exclude it.
- The in-image `bundle install` then found gems already present and skipped
  native rebuilds, shipping host-compiled binaries into the container. On a
  non-Debian host (e.g. Arch) those need the host's `libsasl2.so.3` soname and
  newer glibc than Debian ships.

**Remediation:**

Prevented since the fix: both Ruby services' `.dockerignore` files exclude
`vendor/`, so gems always compile inside the image against its own libraries,
and the adjudicator runtime image installs `libsasl2-2` alongside `libpq5`.
For an already-poisoned cluster (image built before the fix):

```bash
# Rebuild + push with the clean context
docker build -f services/adjudicator-ruby/Dockerfile \
  -t localhost:5001/adjudicator:milestone8 services/adjudicator-ruby
docker push localhost:5001/adjudicator:milestone8

# Bust the k3d node's image cache (imagePullPolicy is IfNotPresent), then roll
docker exec k3d-rube-goldberg-server-0 crictl rmi rghello-registry:5001/adjudicator:milestone8
kubectl delete pod -n rube-goldberg -l app=adjudicator
kubectl rollout status deploy/adjudicator -n rube-goldberg --timeout=150s

# Sanity-check any rebuilt image: expect 0
docker run --rm --entrypoint sh localhost:5001/adjudicator:milestone8 -c \
  'ldd $(ls -d /app/vendor/bundle/ruby/*/gems/rdkafka-*/ext/librdkafka.so) | grep -c "not found"'
```
