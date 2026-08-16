# observability/

Local observability stack: OpenTelemetry Collector, Prometheus, Loki, Tempo,
and Grafana.

> **Note:** The `dashboards/`, `alerts/`, `otel/`, `prometheus/`, `loki/`, and
> `tempo/` subdirectories are scaffolding placeholders and are currently empty.
> The actual, deployed configuration for the observability stack lives in
> `infra/k8s/milestone11/*.yaml` (e.g. `grafana.yaml`, `grafana-dashboards.yaml`,
> `prometheus.yaml`, `loki.yaml`, `tempo.yaml`, `otel-collector.yaml`).

| Directory | Purpose | Milestone |
| --- | --- | --- |
| `dashboards/` | Grafana dashboard JSON (Overview, Run Deep Dive, OCR Lab, Infra) — *scaffolding; see `infra/k8s/milestone11`* | 11 |
| `alerts/` | In-dashboard local alerts — *scaffolding; see `infra/k8s/milestone11`* | 11 |
| `otel/` | Collector configuration (OTLP intake, routing) — *scaffolding; see `infra/k8s/milestone11`* | 11 |
| `prometheus/` | Scrape configuration — *scaffolding; see `infra/k8s/milestone11`* | 11 |
| `loki/` | Loki configuration — *scaffolding; see `infra/k8s/milestone11`* | 11 |
| `tempo/` | Tempo configuration — *scaffolding; see `infra/k8s/milestone11`* | 11 |
