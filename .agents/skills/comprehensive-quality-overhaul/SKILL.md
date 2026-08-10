---
name: comprehensive-quality-overhaul
description: >-
  Run a complete, bounded read-only quality sweep across the applicable code,
  contracts, tests, docs, agent guidance, dependencies, operations, and UI
  surfaces, then produce one deduplicated triage report. Use for "run all
  skills", "comprehensive quality sweep", "improve everything", or a kitchen
  sink review. Implementation and release actions remain parent-owned.
---

# Comprehensive Quality Overhaul

This is a review orchestrator, not an unattended rewrite. It discovers issues
across the repository and consolidates them so the user can choose what to
apply. It does not require five fixed workers or a parallel worktree topology.

## Non-negotiable boundaries

- Read `AGENTS.md`, `.kilo/operating.md`, `docs/architecture.md`, and
  `docs/implementation-status.md` first. The current milestone and integrity
  rules outrank every finding.
- Run only applicable skills. A source skill that assumes Kraken, KMP, Gradle,
  Exposed, or trading behavior is not applicable to this repository; record it
  as skipped rather than importing its assumptions.
- Discovery workers are read-only, bounded, and assigned disjoint paths. The
  parent owns triage, edits, docs synchronization, gates, and final evidence.
- Never run concurrent `make`, coverage, k3d, infrastructure, or browser-stack
  processes in one clone. Application boot and visual inspection are serial
  parent work.
- Do not create issues, branches, commits, pushes, PRs, or remote/infrastructure
  changes as a default result. Use the release skills only after explicit user
  authorization.

## Review tracks

Choose the smallest set that covers the repository and current request; usually
3–6 tracks, never one worker per skill:

| Track | Typical paths | Applicable skills |
| :--- | :--- | :--- |
| Runtime and integrity | `cmd/`, `services/`, `contracts/` | `code-review`, `ai-slop-detector`, optimizer survey |
| Tests and acceptance | `tests/`, service tests, `docs/architecture.md` | `continuous-quality` discover-only, anti-cheating and integration review |
| Docs and guidance | `docs/`, `AGENTS.md`, `.agents/`, `.kilo/`, harness projections | `documentation-review`, `rules-and-skills-audit`, `skill-reviewer`, comments |
| Build and operations | `Makefile`, `versions.env`, `scripts/`, `infra/`, `.github/` | `dependency-upgrade`, build/security review |
| UI and documentation evidence | `services/web-shell/`, `services/artifact-inspector-ruby/`, `web/`, `docs/screenshots/` | `ui-manual-qa`, `docs-screenshot-refresh`, user-guide review; parent boots the stack serially |
| Architecture and roadmap | `docs/architecture.md`, `docs/backlog.md`, `services/` | `architecture-review` recommendations only |

Use [parallel-multi-agent](../parallel-multi-agent/SKILL.md) and the registered
router for read-only tracks when it reduces latency. Apply the route,
capability, fallback, and worktree rules from `.kilo/operating.md`.

## Workflow

### Step 0 — Scope and baseline

Define whether the sweep covers the working diff, the current milestone, or the
whole repository. Record the starting status and read existing backlogs. Run
the relevant baseline gates serially; for a full sweep:

```bash
STRICT=1 make prerequisites
STRICT=1 make format
STRICT=1 make lint
STRICT=1 make unit
STRICT=1 make coverage
STRICT=1 make build
```

Add `make integration` and `make e2e` when the acceptance stack or cross-service
contracts are in scope. A failed baseline is a finding, not permission to
invent a green result.

### Step 1 — Discover

Brief each track with the absolute repository path, exact allowed paths, current
status, acceptance criteria, iteration cap, and a compact report limit. Workers
must not run gates, boot infrastructure, inspect secrets/runtime state, or edit
outside their scope. The parent records partial or unavailable tracks.

### Step 2 — Validate and deduplicate

The parent checks each finding against source, contracts, tests, and current
docs. Merge duplicate reports, reject preference-only claims, and distinguish a
missing test from a production defect. Classify impact:

| Size | Meaning | Decision |
| :--- | :--- | :--- |
| **S** | Local doc, test, link, or cleanup correction | Candidate for approved follow-up |
| **M** | One-service or one-guidance-area change within existing boundaries | Candidate after ownership check |
| **L** | Contract, integrity, architecture, infra, generated output, or acceptance change | Stop and ask |

### Step 3 — Deliver triage, not automatic patches

```markdown
# Comprehensive quality overhaul — YYYY-MM-DD

## Scope and baseline
- …

## Findings
| ID | Domain | Size | Path | Evidence | Recommendation | Depends on |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| … | … | S/M/L | … | … | apply / ask / defer / drop | … |

## Skipped source-only skills
- Skill — why its assumptions do not apply here

## Verification gaps and residual risk
- …

## Suggested apply order
- …
```

If the user then authorizes implementation, switch to
[continuous-improvement](../continuous-improvement/SKILL.md), the owning
specialized skill, or the milestone workflow. Keep architecture and integrity
items gated for explicit approval and run all final checks in the parent.

## Completion checklist

- [ ] Current milestone, architecture, and integrity constraints read
- [ ] Every applicable track has a bounded scope and compact result
- [ ] Source-only/domain-mismatched skills recorded as skipped
- [ ] Findings validated against code and deduplicated
- [ ] S/M/L and apply/ask/defer decisions are explicit
- [ ] Final gates and UI evidence gaps are reported
- [ ] No release or remote side effect occurred
