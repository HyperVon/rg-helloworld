---
name: reduce-code-size
description: >-
  Behavior-preserving code-size reduction across the repository's services —
  measure first, apply a reduction ladder, and verify with the full gates.
  Use when the user asks to shrink files, cut code size, split large files,
  or reduce LOC without changing behavior.
---

# Reduce Code Size

Size is an investigation trigger, not a defect. Reduce only when the reduction
ladder shows a real win and every safety rule holds.

## Workflow

1. **Baseline** — measure before touching anything:

   ```bash
   wc -l services/*/src/**/*.{go,kt,java,cpp,cs,py,ts,js,rb,rs} 2>/dev/null \
     | sort -n | tail -20
   ```

       Record per-file and per-service totals for the before/after report.

    Before deleting anything, verify dynamic usage so a "dead" symbol is not
    actually reached by reflection or registration:

    - Check serialization schemas (Pydantic/dataclass/ORM/protobuf/JSON) where
      fields are accessed dynamically.
    - Check `**kwargs` forwarding, DI containers, and reflection lookups
      (`getattr`, `__dict__`).
    - Check public plugin or event-handler entrypoints registered via string
      names or decorators.
2. **Read the owner rules** — `AGENTS.md`, `docs/architecture.md` §7, and
   the owning service's conventions. The reduction must preserve every
   integrity rule, wire format, and fail-closed behavior.
3. **Reduction ladder** (apply in order, stop when the next rung is not a
   net win):
   1. Delete dead code (unused imports, unreachable branches, commented-out
      blocks, unused helpers) — verified by the per-language linter.
   2. Reuse existing local helpers instead of duplicating.
   3. Use builders/copy/standard-library idioms already present in the repo.
   4. Extract at 3+ genuine uses, with a cohesive name — never for a single
      use site.
   5. Language features the codebase already uses (no new patterns).
   6. Dependency changes only when the net cost is lower (smaller, pinned,
      verified) — never to silence a warning.
4. **Large-file splits** — split only by reason-to-change (one cohesive
   concern per file), with a name that reduces merge overlap. Treat ~800
   lines as an investigation trigger per language; do not split mechanically.
5. **Refactor in cohesive slices** — each slice compiles and tests green
   before the next. Run the per-language formatter after each slice.
6. **Verify** — `STRICT=1 make prerequisites`, `STRICT=1 make format`,
   `STRICT=1 make lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`, and
   `STRICT=1 make build`; plus `make integration`/`make e2e` when
   cross-service behavior is touched. Confirm test counts did not drop.

## Safety rules

- Preserve public behavior, wire formats, protocol framing, and maturity-rank
  semantics. Never collapse a trust boundary.
- Never delete a distinct test case to reduce size; tests are evidence, not
  overhead.
- Contract tests must use independent raw literals for wire contracts — never
  derive the expected value from the same constant the implementation uses.
- Do not widen coverage exclusions to buy LOC.
- A "reduction" that changes error handling, retries, or idempotency keys is
  a behavior change — stop and treat it as one.
- Avoid the cross-domain DRY trap: do not unify superficially similar code
  across different business domains or reasons to change. Extract a shared
  helper only for genuinely reusable, cohesive logic with one clear owner.
- Reject code golfing: never cut LOC at the cost of readability. Specifically
  reject replacing clean `if/else` with deeply nested ternary or boolean
  short-circuit hacks, collapsing explicit error checks into a generic handler,
  or dropping type annotations/comments to deflate the count.
- Preserve git-blame hygiene: avoid purely cosmetic reordering of functions or
  moving files across directories unless the split aligns with an established
  ownership boundary.

## Report

```markdown
# Code-size reduction — YYYY-MM-DD

## Before → after
- per-file/per-service totals

## Changes by ladder rung
- …

## Verification
- gates run; test counts before → after; remaining risks
```

Commit via [commit-and-push](../commit-and-push/SKILL.md) only when the user
asks. For evidence-backed cleanup audits without a size goal, use
[ai-slop-detector](../ai-slop-detector/SKILL.md) instead.
