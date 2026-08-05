---
name: autonomous-code-optimizer
description: >-
  Unattended multi-pass cleanup loop — repeats bounded passes over code,
  tests, docs, and guidance until a full cycle finds zero issues, improving in
  place without redesigning boundaries. Use when the user asks for an
  autonomous cleanup, multi-pass refactor, "de-slop without stopping", or an
  unattended quality pass. Not a replacement for milestone or PR workflows.
---

# Autonomous Code Optimizer

Run bounded cleanup passes until a full cycle finds zero actionable issues.
**Improves in place; never redesigns boundaries.** Milestones, contracts, and
integrity rules stay authoritative — this skill only refines within them.

## Stance

- One concern per pass; verify each pass before the next.
- Every edit must preserve public behavior, wire formats, integrity rules,
  and fail-closed semantics.
- Stop and ask before: architecture changes, contract changes, dependency
  changes, behavior changes to the CLI's printed output, or any edit to
  `tests/anti-cheating/` assertions.
- Never edit generated code under `contracts/`; regenerate via `make
  contracts` when definitions change (and that needs approval).

## Passes (repeat until a full cycle finds zero issues)

### Pass 1 — Static quality & security

- Fully-qualified names, absolute user paths, magic strings, dead code,
  unused imports/exports, secrets or credentials in source, `latest` tags or
  unpinned versions in `versions.env`/lockfiles.
- Lint-first: run `make lint` and fix only what it flags.

### Pass 2 — Integrity, protocols & concurrency

- Verify `docs/architecture.md` §7 invariants in touched code: no
  plaintext/expected-character fields downstream of glyph planning; CLI
  prints only `assembledText`.
- Maturity ranks only increase; artifacts record input IDs and SHA-256
  hashes.
- Kafka consumers idempotent (deterministic operation IDs); large payloads
  in MinIO, not Kafka/logs/Redis.
- Cancellation and retry/backoff handled; no silently swallowed failures.

### Pass 3 — Architecture & lean code

- Pattern integrity: contract-first boundaries; one language per service;
  no bypassed protocols; no wrappers without a seam; no guards for
  impossible states; no fallbacks that mask hard failures.

### Pass 4 — Verify

- Re-run everything with forced re-execution — never trust cached green:

  ```bash
  make format
  make lint
  make unit
  make coverage
  ```

  Plus `make integration` / `make e2e` when the change touches
  cross-service behavior. Compare test counts before/after; a green result
  with the same count means the tests did not actually run.

## Design principles (apply when editing)

1. Fail closed: unknown or unverifiable states fail hard, not silently.
2. Stable identity: operation IDs and artifact hashes are deterministic.
3. Validate each invariant once, at its owning boundary.
4. Cancellation is control flow: propagate it.
5. Least privilege: no new credentials or broader permissions.
6. Pure core / impure shell: keep protocol and I/O at the edges.
7. Delete and extract over abstract: remove dead code before adding
   abstractions.
8. Observability without secrecy: structured logs, never plaintext or
   secrets.
9. Coverage is evidence: each test kills a distinct defect class.
10. One language per service; never combine or bypass.

## Convergence rule

A cycle is **not clean** if any pass produced a fix that was not followed by
its verification, if gates were skipped, if a later pass invalidated an
earlier fix, or if the same defect class reappeared in a different file.
Repeat the loop until a full cycle finds zero issues, then stop and report.
Never count a partial cycle as complete.

## Report

```markdown
# Autonomous optimization — YYYY-MM-DD

## Cycles
- cycle N: X fixes (pass 1/2/3), gates: pass

## Changes by category
- …

## Verification
- test counts before → after; gates run serially; remaining risks

## Deferred (needs approval)
- …
```

Ship fixes via [commit-and-push](../commit-and-push/SKILL.md) /
[open-pr](../open-pr/SKILL.md) only when the user asks. For a bounded audit
without edits, use [ai-slop-detector](../ai-slop-detector/SKILL.md) instead.
