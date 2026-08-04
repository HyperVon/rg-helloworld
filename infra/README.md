# infra/

Local infrastructure as code.

| Directory | Purpose | Milestone |
|---|---|---|
| `k3d/` | `cluster.yaml` for the local k3s cluster and registry | 2 |
| `terraform/` | Terraform root module, modules, and the `local` environment | 2 |
| `helm-values/` | Pinned Helm value files for Kafka, Prometheus, Loki, Tempo, Grafana | 2 |
| `kubernetes/` | Hand-written manifests (secrets, jobs, cronjobs, network policies) | 2 |
