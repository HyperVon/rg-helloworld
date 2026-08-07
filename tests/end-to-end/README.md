# End-to-end tests

Full acceptance run for the current milestone.

```bash
make e2e
```

## Milestone 0

The Milestone 0 e2e test proves the complete repository acceptance from a
clean state:

1. `make prerequisites`
2. `make format`
3. `make lint`
4. `make unit`
5. `make build`
6. Integration harness (every built artifact's banner asserted)

Set `E2E_SKIP_GATES=1` to skip the gates (CI uses this because the matrix
jobs already run them):

```bash
E2E_SKIP_GATES=1 make e2e
```

## Later milestones

The primary acceptance test arrives in Milestone 9:

```bash
OUTPUT="$(rghw run --quiet)"
test "$OUTPUT" = "Hello World"
```

plus assertions on run status, maturity ranks, artifact lineage, OCR
artifacts, traces, UI projection, prohibited-field scans, and stream
cleanliness (architecture section 27.5).
