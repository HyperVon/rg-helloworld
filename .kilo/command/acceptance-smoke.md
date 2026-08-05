---
description: "Boot the acceptance stack and verify the pipeline smoke"
subtask: true
---

# Acceptance Smoke

Run a safe, isolated acceptance smoke check and report whether the stack
boots and the pipeline completes.

- Read `AGENTS.md`, `docs/runbook.md`, and the `rghello-milestone` skill
  first.
- Do not read or copy `.local/`, `.env` files, kubeconfigs, MinIO
  credentials, database files, logs, home-directory files, or any external
  runtime data.
- Use the checked-in Makefile targets and `scripts/` as the only launch
  implementations. Do not reproduce their shell, JSON, port, or
  process-management logic inline.
- Boot the stack through the repository's own targets, in order:
  `make prerequisites`, `make contracts`, `make cluster` (k3d), `make infra`,
  `make wait`, then `make demo` (the smoke test) — or `make e2e` when the
  current milestone requires the full acceptance suite.
- Start long-lived steps (cluster creation, wait loops) as tracked background
  processes and poll for readiness with bounded log patterns; never leave the
  user waiting on a foreground command that never exits.
- Do not add fixed ports or request private endpoints; the repository's
  scripts own ports and health checks.
- Tear down what you started: run `make down` after the smoke completes, and
  clean up only your own temporary artifacts. Preserve `.local/` persistent
  directories.
- Report only build status, startup status, smoke/e2e status, and a redacted
  failure summary. Do not include raw logs, credentials, account data,
  personal paths, cluster secrets, or database contents.

If the stack cannot be started safely without touching a real local config,
cluster, or database, stop and report that limitation instead of proceeding.
