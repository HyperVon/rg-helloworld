---
name: continuous-quality
description: >-
  QA-cycle orchestrator — hardens correctness of the current milestone or
  change set: baseline gates first, deliberately invent edge cases, test-first,
  verify with forced re-execution, and persist a quality backlog. Use when the
  user asks to harden tests, close coverage gaps, find edge cases, run a QA
  loop, or improve reliability of a milestone.
---

# Continuous Quality

A QA-cycle orchestrator (sibling to the milestone workflow): its job is to
make the current milestone or change set **provably correct**, not just
shipped. Individual skills must stay usable alone — this skill only
orchestrates them.

## Mode and stop conditions

| Mode | Stop condition |
| :--- | :--- |
| **Cycle** (default) | One full QA pass: baseline gates → discovery → fixes → verification report |
| **Loop** | Repeat cycles until a full cycle finds no actionable items (ask before the 4th cycle) |
| **Discover-only** | Stop after findings are written to the backlog; no fixes |

Classify every candidate item as **S** (small: one focused test/fix),
**M** (medium: one service or test area), or **L** (large: multiple services,
contract changes, or e2e work). Impact overrides size: anything touching
integrity rules, secrets, cluster/infrastructure, or public contracts is
**L** regardless of diff size. Test-only items stay S/M unless the assertions
must match wrong production behavior.

## Step 1 — Baseline gates first

Failures here become backlog items, not "expected red":

```bash
STRICT=1 make prerequisites
STRICT=1 make format
STRICT=1 make lint
STRICT=1 make unit
STRICT=1 make coverage
STRICT=1 make build
```

Record gate results and any failures in the
quality backlog **before** starting discovery. Never start discovery on a
broken baseline and call the result "quality".

## Step 2 — Discovery tracks

Use the tracks that match the change surface; for a broad pass use the active
harness's native read-only delegation only after explicit approval and when the
tracks are disjoint (the parent owns triage and edits):

1. **Runtime edges** — deliberately invent edge cases for the changed code:
   boundaries, empty inputs, failure modes, duplicate events, out-of-order
   messages, maturity-rank regressions, retries.
2. **Integrity rules** — audit changed paths against `docs/architecture.md`
   §7: no plaintext downstream of glyph planning; CLI prints only
   `assembledText`; artifacts record input IDs and SHA-256 hashes.
3. **Idempotency / protocol** — Kafka consumers, SSE framing, gRPC/SOAP
   surfaces: deterministic operation IDs, replay safety, backpressure.
4. **Coverage gaps** — find untested branches in changed code; per-language
   coverage must stay >= 90%.
5. **Anti-cheating suite** — `tests/anti-cheating/` must keep passing and
   cover the new behavior; add guards where missing.
6. **Operator use-cases** — CLI invocations, acceptance-mode runs, error
   recovery per `docs/runbook.md`.

## Step 3 — Test-first

For every accepted edge case: write the failing test (red), confirm it fails,
implement the smallest fix (green), then refactor. Do **not** fix by matching
buggy behavior in assertions — if the test reveals wrong production behavior,
the production code is the defect.

Assertion discipline: one sharp assertion per defect class over snapshot soup;
derive expected values from contracts or independent oracles, never from the
implementation's own branch logic.

## Test discipline

Beyond the test-first rule, hold these bar-raising practices on every hardening
slice:

- **Mock contract fidelity.** Never mock the unit under test or its immediate
  contract boundary to make a regression test pass. Do not assert only that a
  mock method was called (`mock.assert_called_once()`); assert the observable
  state, returned value, or protocol side effect. When mocking external
  boundaries (HTTP APIs, cloud storage, Kafka, gRPC), reproduce the production
  error codes, headers, and failure payloads the code must survive.
- **Flakiness and timing.** Never green a flaky or racey test by adding arbitrary
  `sleep()` delays, bumping timeouts, or reordering tests until they happen to
  pass. Use condition-based polling with bounded timeouts, explicit
  synchronization (events, latches, promises, channels) instead of timing
  assumptions, and injected deterministic clocks or mock timers for
  time-dependent logic. Isolate test state (databases, directories, ports) so
  tests do not interfere when run concurrently or out of order.
- **Surgical fix boundary.** The production fix is the smallest change that turns
  the deterministic regression test green. Do not entangle it with stylistic
  cleanup, signature refactoring, or unrelated optimization in the same slice.
- **Test-isolation verification.** Confirm a new test passes both in isolation
  and as part of the full suite (or randomized order), and that its fixtures
  cleanly tear down modified environment variables, monkeypatches, database
  state, and open file descriptors.
- **Incomplete evidence.** A passing command without the relevant test count or
  artifact is incomplete evidence — report the moved count or the gate artifact,
  not just a green line.

## Step 4 — Verify with forced re-execution

Never trust cached green. Re-run the affected gates and confirm the test
**count moved**:

```bash
make unit-<lang> 2>&1 | tee .local/diagnostics/qa-unit.log
```

Compare test counts before/after from the log; a green result with the same
count means the new tests did not actually run. Then rerun the full gates
serially (`STRICT=1 make prerequisites`, `STRICT=1 make format`,
`STRICT=1 make lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`, and
`STRICT=1 make build`). Add `make integration` / `make e2e` when the change
touches cross-service behavior.

## Step 5 — Persist the backlog

Keep the durable [`.agents/quality-backlog.md`](../../quality-backlog.md)
with `open`, `in_progress`, `done`, `deferred`, and `dropped` states so findings
survive context compression. Never leave discoveries only in chat. Do not
create GitHub issues or other remote artifacts automatically; issue tracking is
an explicit user-authorized follow-up.

## Step 6 — Report

```markdown
# Quality cycle — YYYY-MM-DD (mode: cycle|loop|discover-only)

## Baseline
- make prerequisites / format / lint / unit / coverage / build: pass | fail
  (details)

## Findings
- [S|M|L] finding — path — evidence — proposed fix

## Fixed
- …

## Deferred
- … (why)

## Verification
- test counts before → after; gates run; remaining risks
```

Ship fixes via [commit-and-push](../commit-and-push/SKILL.md) /
[open-pr](../open-pr/SKILL.md) only when the user asks.

## Anti-patterns

- Starting discovery on a broken baseline
- Trusting cached green (same test count) as verification
- Fixing tests to match wrong production behavior
- Leaving findings only in chat (no backlog file)
- Editing multiple hot files in parallel workers without a single owner
- Calling a QA cycle complete with unchecked acceptance conditions
