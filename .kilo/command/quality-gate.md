---
description: "Run the repository quality gates without changing files"
subtask: true
---

# Quality Gate

Run a read-only verification pass for this repository.

- Read `AGENTS.md` and `.kilo/operating.md` before choosing commands.
- Do not read or print `.local/`, `.env` files, kubeconfigs, MinIO
  credentials, database files, logs, home-directory files, or any other local
  runtime data.
- Do not edit, format, delete, commit, push, or start long-running processes
  (k3d, servers, watchers).
- Run the full gates serially, one at a time, from the repository root:
  - `make prerequisites`
  - `make format`
  - `make lint`
  - `make unit`
  - `make coverage`
  - `make build`
- Run them once more with `STRICT=1` (missing toolchains must fail).
- Report each command as pass or fail, identify the first actionable failure
  and its file/target, and summarize successful checks.
- Redact credentials, tokens, account identifiers, hostnames, personal paths,
  and personal or account data from command output.

Do not make fixes in this command. This command is for evidence before a
separate implementation or formatting pass.
