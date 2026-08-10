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
