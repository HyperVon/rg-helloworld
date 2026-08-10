---
name: ui-manual-qa
description: >-
  Perform report-only manual QA of the local Web Shell, Artifact Inspector,
  event gateway, and changed observability UI. Exercise real navigation,
  run-selection, artifact, SSE, loading, and error interactions with fresh
  browser evidence. Use for UI smoke tests or click-through QA, not visual
  redesign or screenshot-only refreshes.
---

# UI Manual QA

Test the browser experience as an operator would. Prefer browser snapshots,
interaction results, and fresh screenshots over code inspection alone.

## Boundary

| Skill | Concern |
| :--- | :--- |
| **ui-manual-qa** (this) | Functional interaction pass and report |
| [docs-screenshot-refresh](../docs-screenshot-refresh/SKILL.md) | Committed documentation images |
| [user-guide](../user-guide/SKILL.md) | End-user documentation |
| [architecture-review](../architecture-review/SKILL.md) | Recommend-only system redesign |

Do not redesign or silently fix application code during a QA pass. Hand
approved defects to the owning implementation workflow.

## Scope and preconditions

- Default scope is the full changed UI; a named page or feature may be scoped.
- Use the documented local acceptance stack and routes from `docs/runbook.md`.
  Typical surfaces are Web Shell, Artifact Inspector, event-gateway SSE, and
  Grafana/other observability pages when they changed.
- Use only local/disposable data. Do not connect to an external runtime, expose
  credentials, or mutate a shared deployment without explicit permission.
- Rebuild/redeploy the affected asset and hard-refresh before judging styling or
  interaction. Use phone and laptop captures at minimum; responsive changes
  also cover relevant tablet, desktop, and wide widths.

## Workflow

1. Create a bounded QA evidence directory under `.local/diagnostics/` and note
   the base URLs, build/deploy state, and representative run ID without
   persisting secrets.
2. Confirm the health and initial page state. Verify navigation, page titles,
   visible status, loading/empty states, and that the page does not require
   hidden manual setup beyond the runbook.
3. Exercise the changed controls. For Web Shell, cover run discovery/selection,
   graph state transitions, refresh/reconnect, and artifact links when present.
   For Artifact Inspector, cover landing, run selection, artifact preview,
   invalid/out-of-scope identifiers, and empty/error responses when present.
   For SSE or observability changes, cover reconnect/replay or the changed
   dashboard route.
4. For each case, record setup, action, expected result, actual result, and
   one evidence reference as `pass`, `fail`, or `blocked`. Wait for async
   state to settle and assert visible outcomes, not console silence.
5. If four consecutive interactions fail without new evidence, stop and report
   the blocker rather than producing a misleading partial pass.
6. Finish with fresh screenshots at the required widths, then summarize the
   report and hand off findings without editing application code.

## Report format

```markdown
# UI manual QA — YYYY-MM-DD
- Scope: …
- Result: N passed / N failed / N blocked
- Stack/build/run: …

## Failures
### [P0|P1|P2] CASE — outcome
- Steps: …
- Expected: …
- Actual: …
- Evidence: `.local/diagnostics/...`

## Passed / blocked
- …
```

P0 is navigation failure, data loss, or integrity/safety confusion; P1 is a
broken control or wrong visible result; P2 is a localized polish or timing
issue. Preserve failed evidence for review. Do not call a page healthy because
one static screenshot rendered.

## Cleanup and completion

- Stop only processes started for this QA run; preserve shared infrastructure
  and unrelated user work.
- Keep evidence until the user has reviewed it, then remove only disposable
  artifacts that the run created.
- [ ] Changed interactions exercised at the relevant routes
- [ ] Async, empty, error, and terminal states checked where applicable
- [ ] Fresh multi-viewport evidence captured and read
- [ ] Findings include expected/actual/evidence and no fixes were smuggled in
