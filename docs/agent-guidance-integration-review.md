# Cross-project agent guidance review

Reviewed 2026-08-09. This records the comparison of the source project's 41
portable skills with this repository's agent guidance. It is a decision record,
not a copy of the source project's domain playbook. Re-run
`rules-and-skills-audit` if either project's skill set changes materially.

## Integrated or adapted

These skills fill real gaps in this repository and were rewritten against its
polyglot, contract-first, local-only architecture:

| Skill | Integration |
| :--- | :--- |
| `code-review` | Added a general evidence-based diff/subsystem review for service boundaries, integrity, protocols, tests, docs, and UI evidence. |
| `continuous-improvement` | Added a bounded broad-improvement cycle using the existing quality backlog; no implicit issues, commits, pushes, or PRs. |
| `comprehensive-quality-overhaul` | Added a read-only all-applicable-skills sweep with parent-owned triage and serial gates. |
| `docs-screenshot-refresh` | Added a local-stack workflow for refreshing and visually inspecting `docs/screenshots/`. |
| `ui-manual-qa` | Added report-only click-through QA for Web Shell, Artifact Inspector, SSE, and changed observability surfaces. |
| `post-deploy-ui-smoke` | Added a short read-only hard-refresh and critical-status check that escalates to full UI QA. |
| `user-guide` | Added maintenance rules for `docs/user-guide.md`, current routes, commands, and screenshot honesty. |

Portable operating guidance also incorporated into `.kilo/operating.md` and its
harness projections includes isolated/disjoint delegation, serial final gates,
background process hygiene, host-enforceable route evidence, projection
alignment, path/credential hygiene, and fresh responsive UI evidence.

## Existing equivalents or merges

No duplicate skill was created for these source skills:

| Source skill | Decision |
| :--- | :--- |
| `adversarial-pr-review` | Existing current skill already owns bounded PR review; portable routing and isolation gaps were folded into operating norms. |
| `ai-slop-detector` | Existing polyglot/integrity-aware audit is the better local owner. |
| `architecture-review` | Existing milestone- and integrity-aware recommendation workflow is narrower and safer here. |
| `autonomous-code-optimizer` | Existing local bounded cleanup loop covers the source concept without KMP/trading passes. |
| `commit-and-push` | Existing version preserves explicit authorization and milestone documentation. |
| `complex-code-comments` | Existing language-neutral comment hygiene skill is sufficient. |
| `continuous-quality` | Existing QA-only orchestrator is the sibling owner; its backlog path and no-implicit-remote-side-effect rule were clarified. |
| `dependency-upgrade` | Existing multi-language pinned-version workflow is more applicable than the source's Gradle/Dependabot assumptions. |
| `documentation-review` | Existing source-truth audit already covers architecture, runbook, ADRs, skills, and config. |
| `open-pr` | Existing contract/e2e/anti-cheating gates and adversarial handoff are authoritative. |
| `parallel-multi-agent` | Existing polyglot ownership, route selection, worktree, and serial-gate rules are authoritative. |
| `reduce-code-size` | Existing service-wide behavior-preserving reduction workflow is sufficient. |
| `rules-and-skills-audit` | This review used the existing audit skill; no second auditor is needed. |
| `skill-authoring` | Existing local authoring contract was used for the new skills. |
| `skill-reviewer` | Existing content-review workflow remains the recommendation-only owner. |
| `todo-resolution` | Existing project-safe TODO workflow is sufficient. |
| `changelog-and-docs-sync` | Merged conceptually into `docs-sync`; this repository has no source-project `CHANGELOG`/KMP package-tree contract. |

## Kept source-only

These skills encode assumptions that do not exist here and were intentionally
not copied:

`common-kmp-module`, `coroutines-flows-sse`, `dry-run-and-simulation`,
`exposed-repository`, `frontend-js-development`, `gradle-quality-gates`,
`koin-di-and-config`, `kotlin-refactoring-and-cleanup`,
`kraken-api-integration`, `ktor-html-views`, `portfolio-rebalancing-math`,
`trade-history-sync`, and `write-kotest` are Kotlin/KMP/Gradle/Exposed/Kraken/
trading-specific.

`ui-visual-guidance-and-aesthetics`, `ui-visual-implement`, and
`ui-visual-review` contain the source project's exact trading-dashboard visual
language and page contracts. Their useful general principles—recommend before
redesign, fresh screenshot evidence, responsive coverage, and visual
verification after implementation—are represented in the operating norms and
the adapted UI/screenshot skills; their aesthetic rules are not.

`product-opportunity-review` remains available as a future recommendation if a
product-roadmap request warrants it. It was not added as an engineering
workflow because this repository's active contract is milestone acceptance,
not a trading-product roadmap.

## Guardrails preserved

- Milestone order, anti-cheating boundaries, maturity ranks, artifact hashes,
  contract-first generation, language ownership, pinned dependencies, and local
  acceptance remain authoritative.
- Broad workflows discover and triage first; L-class architecture, contract,
  integrity, infrastructure, generated-output, and acceptance changes stop for
  approval.
- No adapted workflow creates remote issues, commits, pushes, opens PRs, or
  changes shared infrastructure unless the user separately authorizes it.

## Agent-project-foundation bridge

On the dedicated `codex/agent-foundation-integration` branch, the reusable
agent-project-foundation was run against the repository before the bridge files
were added, without executing any provider, source script, installer, or MCP
server. The pre-bridge baseline (2026-08-09, digest
`734d1c5225ec32d3bb9421fb3cd238fd5320f4812d1efc61b732bd83f5db9b20`) contained 4,069
relevant files, 72 guidance files, and 25 skills; counts after the bridge
include the added `agent-foundation-audit` skill and therefore differ.

The scanner reviewed 3,660 files and produced 3,436 findings: 724 high,
459 medium, and 2,253 low. These are review signals rather than proof of
malice; many are expected because this repository intentionally contains
credential-handling rules, scripts, infrastructure, test fixtures, and
provider configuration examples. High findings remain a stop condition before
external guidance is activated.

The branch adds only a portable bridge:

- `.agents/skills/agent-foundation-audit/SKILL.md` defines the trigger,
  provenance boundary, preservation rules, and completion contract.
- `scripts/agent-foundation-audit.sh` provides a shell-only entry point for
  inventory and scanning; it writes reports outside the repository by default
  and never applies a plan.
- The existing canonical rules and skill index now route external guidance
  work to that bridge. Existing domain skills and the model router remain
  unchanged.
- The foundation now also supports a new/empty-project path through an
  approval-gated `init` wrapper and a harness-neutral `handoff` report; Rube
  uses only the audit portion because it is an existing project.

For an external source, the next operation is still an explicit foundation
`plan` against this checkout. A safe candidate may be copied only to inactive
`.agent-foundation/vendor` storage; local collisions remain canonical and
unsafe candidates remain quarantined. This bridge does not make any external
skill active automatically.

## Structural audit outcome

### Inventory summary

The audit reviewed the canonical rules (`AGENTS.md`, `.kilo/operating.md`),
the thin harness projections (`CLAUDE.md`, Copilot, Cursor, Windsurf, and Kilo
configuration), the existing cross-project review, model-router instructions,
and the repository's skill-authoring, skill-reviewer, and rules-and-skills-audit
contracts. The remaining domain skills were inventoried but not individually
rewritten because this change does not alter their content or ownership.

### Findings

- **Improvement:** there was no portable, repository-local entry point for
  safely invoking the reusable foundation against an existing project. The new
  `agent-foundation-audit` skill and shell wrapper close that gap.
- **Keep separate:** `agent-foundation-audit` owns provenance/scanning and
  external-source staging; `rules-and-skills-audit` owns structural overlap and
  drift; `skill-reviewer` owns content-depth recommendations; the model router
  owns provider selection. Their triggers and decision boundaries are distinct.
- **No conflict found:** `AGENTS.md` and `.kilo/operating.md` already make
  local guidance canonical and projections thin, so no domain skill or router
  change is justified by this integration.

### Reversible consolidation plan

1. Keep the bridge additive and use it for read-only baselines first.
2. For each external source, require a pinned revision, scan, plan review, and
   branch-local apply.
3. Promote vendor content only after a separate harness-specific review; do
   not merge the bridge into domain skills by default.
4. Re-run this structural audit if the foundation contract or skill tree
   changes materially.

### No-change conclusion

No existing Rube skill, canonical invariant, harness projection, or model-router
implementation should be merged, deleted, or rewritten as part of this first
bridge. The branch intentionally adds only the missing trust-boundary workflow.
