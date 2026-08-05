# tests/

Contract, integration, end-to-end, chaos, and anti-cheating test suites.

| Directory | Purpose | Milestone |
| --- | --- | --- |
| `contract/` | Schema, SOAP XSD, gRPC, and REST contract tests | 1 |
| `integration/` | `run_integration.sh`: cross-language artifact harness; later Kafka/PostgreSQL/Redis/MinIO/SOAP/gRPC/SSE suites | 0 (harness), 2+ (platform) |
| `end-to-end/` | `run_e2e.sh`: full milestone acceptance; later `rghello run` -> "Hello World" | 0 (gates), 9 (pipeline) |
| `chaos/` | Minimal chaos test (rasterizer pod kill) | 12 |
| `anti-cheating/` | Prohibited-field scans and printer enforcement | 1+ |

Each directory contains a README once its milestone starts.
