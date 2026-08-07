# Runbook

## Prerequisites

- Docker runtime (Colima on macOS, Docker Desktop on Windows/Linux)
- k3d, kubectl, helm, terraform
- Go 1.26+, Rust 1.97+, Node.js 20+, Python 3.11+, Ruby 3.4+, Java 21, .NET 10

## Full `make demo` sequence

```bash
make prerequisites   # toolchain check + language deps
make format          # format all languages
make lint            # lint all languages
make build           # compile everything
make unit            # unit tests for all services
make integration     # cross-language artifact integration tests
make e2e             # full milestone acceptance (gates + integration)
```

## `rghw run` usage

```bash
# Start a run against the local k3d cluster
rghw run

# Stream live updates via SSE
# The CLI connects to the orchestrator's SSE endpoint and prints progress

# Exit codes:
#   0 — run succeeded and `Hello World` was printed
#   1 — run failed or stack unavailable
```

## Recovering from partial infrastructure state

### Pods stuck in CrashLoopBackOff

```bash
kubectl get pods -n rube-goldberg
kubectl logs -n rube-goldberg pod/<pod-name> --previous
kubectl rollout restart deployment/<deployment-name> -n rube-goldberg
```

### Kafka broker unavailable

```bash
kubectl get pods -n rube-goldberg -l app=kafka
kubectl describe pod -n rube-goldberg <kafka-pod-name>
# If the pod is healthy but unreachable, restart the network policy:
kubectl rollout restart statefulset/kafka-controller -n rube-goldberg
```

### MinIO bucket missing

```bash
kubectl exec -n rube-goldberg deploy/minio -- mc ls local/rube-goldberg-artifacts
# Recreate if missing:
kubectl exec -n rube-goldberg deploy/minio -- mc mb local/rube-goldberg-artifacts
```

### PostgreSQL connection refused

```bash
kubectl get pods -n rube-goldberg -l app=postgresql
kubectl logs -n rube-goldberg pod/<postgres-pod-name>
# Check service endpoint:
kubectl get svc -n rube-goldberg postgresql
```

## Diagnostics collection

```bash
# Collect pod logs for all services
kubectl logs -n rube-goldberg -l app=run-orchestrator > /tmp/orchestrator.log
kubectl logs -n rube-goldberg -l app=ocr-worker > /tmp/ocr-worker.log
kubectl logs -n rube-goldberg -l app=adjudicator > /tmp/adjudicator.log
kubectl logs -n rube-goldberg -l app=phrase-assembler > /tmp/phrase-assembler.log

# Collect Kafka consumer group lag
kubectl exec -n rube-goldberg <kafka-pod-name> -- kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group phrase-assembler-v1

# Collect MinIO bucket inventory
kubectl exec -n rube-goldberg deploy/minio -- mc ls -r local/rube-goldberg-artifacts

# Collect PostgreSQL connections
kubectl exec -n rube-goldberg <postgres-pod-name> -- psql -U postgres -c \
  "SELECT * FROM pg_stat_activity;"
```

## `make down` and `make destroy` semantics

```bash
make down        # Delete the k3d cluster (preserves Terraform state)
make destroy     # Terraform destroy for local infrastructure (requires k3d up)
```

**Order matters:** run `make down` before `make destroy` to avoid k3d/Terraform state conflicts.
