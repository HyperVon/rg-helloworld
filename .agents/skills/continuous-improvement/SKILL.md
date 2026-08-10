---
name: continuous-improvement
description: >-
  Orchestrate a bounded improvement cycle across code, tests, contracts,
  documentation, dependencies, operations, and UI evidence. Classify findings,
  apply only approved in-scope changes, run serial quality gates, and stop at
  milestone, integrity, architecture, or external-side-effect boundaries.
  Use for continuous improvement, whole-repository cleanup, or "run with it";
  use continuous-quality for a QA-only loop.
---

# Continuous Improvement

This is the broad improvement orchestrator. It sequences existing skills; it
does not replace `continuous-quality`, `autonomous-code-optimizer`,
`documentation-review`, or the milestone workflow.

## Boundary and safety contract

- Improve the current milestone or change set without advancing the milestone
  sequence. `docs/implementation-status.md` and `docs/architecture.md` remain
  authoritative.
- S/M work may be applied only within the user's approved scope. Stop and ask
  before contract, integrity, architecture, infrastructure, generated-code,
  CLI-output, or acceptance changes; these are L regardless of diff size.
- Parent-owned integration, backlog updates, serial gates, and final evidence
  are mandatory. Workers are read-only scouts unless a separate, explicit
  implementation delegation authorizes a disjoint worktree.
- Never create GitHub issues, commit, push, open a PR, change remote state, or
  modify live infrastructure as an automatic part of a cycle. Use
  [commit-and-push](../commit-and-push/SKILL.md) or [open-pr](../open-pr/SKILL.md)
  only after the user separately requests that release action.

## Modes and stop conditions

| Mode | Completion |
| :--- | :--- |
| **Cycle** (default) | One discovery → approved fixes → verification report |
| **Loop** | Repeat bounded cycles until the user stops, the requested count is reached, or a clean cycle finds no actionable item |
| **Discover-only** | Record and classify findings; do not edit application or guidance files |

Pause immediately when an L item needs a decision, a baseline gate reveals an
unknown repository failure, or the next change would cross a milestone boundary.

## Durable tracking

- Use `.agents/quality-backlog.md` for technical findings with `open`,
  `in_progress`, `done`, `deferred`, or `dropped` state. Do not leave findings
  only in chat.
- Use `docs/backlog.md` for optional architecture/product work that must not
  delay the primary milestone sequence.
- Do not invent GitHub issue or label workflows. Remote issue tracking is an
  explicit user-authorized follow-up, not a default cycle side effect.

## One cycle

### Step 0 — Read current truth

Read `AGENTS.md`, `.kilo/operating.md`, the current implementation-status
section, relevant architecture sections, existing backlog entries, and the
working-tree status. Preserve unrelated user changes. Define the change and
the acceptance condition before discovering improvements.

### Step 1 — Baseline and bounded discovery

Run relevant baseline checks serially. For a repository-wide cycle, use:

```bash
STRICT=1 make prerequisites
STRICT=1 make format
STRICT=1 make lint
STRICT=1 make unit
STRICT=1 make coverage
STRICT=1 make build
```

Record failures in the backlog before calling the baseline clean. Add
`make integration` and `make e2e` when cross-service behavior or acceptance
artifacts are in scope. Then select only disjoint discovery tracks that fit:

- [code-review](../code-review/SKILL.md) for runtime, boundary, and integrity
  findings;
- [ai-slop-detector](../ai-slop-detector/SKILL.md),
  [complex-code-comments](../complex-code-comments/SKILL.md), and
  [todo-resolution](../todo-resolution/SKILL.md) for artifact hygiene;
- [documentation-review](../documentation-review/SKILL.md) and
  [docs-sync](../docs-sync/SKILL.md) for source/doc drift;
- [dependency-upgrade](../dependency-upgrade/SKILL.md) for read-only version
  and security inventory;
- [ui-manual-qa](../ui-manual-qa/SKILL.md) or
  [docs-screenshot-refresh](../docs-screenshot-refresh/SKILL.md) when UI/docs
  screenshots are affected;
- [architecture-review](../architecture-review/SKILL.md) for recommendations
  only. Architecture findings are always L.

Use `parallel-multi-agent` and the registered router for bounded read-only
fan-out. Apply the model-selection and worktree rules in `.kilo/operating.md`;
never run concurrent `make`, coverage, k3d, or browser-stack gates in one clone.

### Step 2 — Classify and gate

Classify each distinct finding before editing:

| Size | Examples | Action |
| :--- | :--- | :--- |
| **S** | Local test, doc correction, broken link, small dead-code cleanup | Apply when within the approved scope |
| **M** | One-service refactor, focused guidance sync, non-breaking test or UI fix | Apply only if ownership and gates remain clear |
| **L** | Contract/protocol/integrity change, architecture or infra work, generated output, acceptance behavior, broad redesign | Stop and ask for a decision |

Impact overrides size. Record every item and its evidence in the appropriate
backlog before applying changes. Deduplicate against existing open/deferred
items.

### Step 3 — Apply the smallest approved set

Apply S/M changes in dependency order, one coherent concern at a time. Follow
the owning skill and update documentation in the same change. Do not edit
generated contract output by hand, combine service languages, add floating
versions, weaken anti-cheating tests, or hide a failing baseline.

### Step 4 — Verify with fresh evidence

After each concern, rerun its targeted checks. At the end, rerun the applicable
full gates serially and compare test counts before/after when tests changed.
For UI changes, hard-refresh or rebuild assets, exercise changed interactions,
and capture/read fresh phone, tablet, laptop, desktop, and wide evidence when
responsive behavior changed. Keep temporary logs and screenshots under
`.local/diagnostics/`.

### Step 5 — Synchronize and report

Use [docs-sync](../docs-sync/SKILL.md) for behavior, command, architecture,
runbook, user-guide, or screenshot changes. Update
`docs/implementation-status.md` before and after milestone work only; ordinary
cleanup must not fabricate a milestone entry. Move verified findings to
`done`, preserve deferred L items with their reason, and report remaining risk.

## Cycle report

```markdown
# Continuous improvement — YYYY-MM-DD (cycle|loop|discover-only)
- Baseline: pass | fail | partial, with gates and evidence
- Findings: S/M/L counts and backlog IDs
- Applied: files and focused changes
- Deferred: decision, blocker, or acceptance boundary
- Verification: targeted and full gates; UI evidence when applicable
- Release action: not performed unless separately authorized
```

## Anti-patterns

- Calling a red baseline a clean improvement cycle
- Running a full optimizer loop inside every discovery track
- Treating a role label as model or route evidence
- Parallel edits to contracts, shared docs, or generated outputs
- Using screenshots without a fresh asset build or interaction evidence
- Opening issues, committing, pushing, or creating a PR by implication
