---
description: Run all milestone gates and report results
subtask: true
---
Run the full verification gates for this repository from the root:

1. `make prerequisites`
2. `make format`
3. `make lint`
4. `make unit`
5. `make coverage`
6. `make build`

Then run them once more with `STRICT=1` (missing toolchains must fail).
Capture verbose output to `.local/diagnostics/` and report only the
per-language pass/fail summary plus any failure excerpts. Do not fix
failures unless asked.
