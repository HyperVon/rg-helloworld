---
description: Implement the next milestone in order
subtask: true
---
Implement the next unstarted milestone of this repository, in order.

1. Read `docs/architecture.md` section 29 and the architecture sections
   relevant to the milestone.
2. Read `docs/implementation-status.md` and confirm the current milestone's
   acceptance conditions pass before starting.
3. Update `docs/implementation-status.md` with the milestone scope, tasks,
   and acceptance conditions.
4. Implement the smallest complete milestone; add tests before proceeding.
5. Run targeted checks during iteration (per-language `make unit-*`,
   `make build-*`), then the full gates: `make format`, `make lint`,
   `make unit`, `make coverage`, `make build`.
6. Update documentation and the implementation-status verification log.
7. Do not commit unless explicitly authorized. Report: files created,
   commands executed, test results, remaining limitations, and the next
   milestone.
