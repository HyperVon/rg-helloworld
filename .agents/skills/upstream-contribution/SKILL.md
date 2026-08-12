---
name: upstream-contribution
description: >-
  Let a kit adopter scan its local skills and diverged receipts for generic
  improvements and propose them upstream. Use when an adopter wants to
  contribute a local skill or an improvement to an adopted skill back to the
  Agent Guidance Kit via a fork, branch, and pull request.
---

# Upstream Contribution

Make every kit adopter a potential contributor without auto-publishing.
The proposer runs in the target repository; the maintainer reviews via
`skill-reviewer` intake on this repository.

## Contract

- **Input:** target repository with local `.agents/skills/`, receipt history,
  divergence, and intended kit fork/remote.
- **Output:** provenance-tracked evidence table proposing
  `IMPROVE_EXISTING`/`NEW_SKILL`/`PROJECT_SPECIFIC`/`DEFER`/`REJECT` candidates,
  plus — only after explicit approval — a fork/branch/PR.
- **Owner:** adopter-to-kit contribution workflow.
- **Non-goals:** automatic pushing, bulk export of local skills, or claiming
  that a local skill is generically useful without evidence.
- **Side effects:** read-only until approval; afterward only `git` and `gh`
  operations the user explicitly authorized, on the approved fork/branch.

## Workflow

1. **Inventory the target.** Run `inventory_project.py` and inspect
   `.agents/.agent-guidance-kit/receipts/`, locally created skills, and
   `source_digest != target_digest` divergences. List every local skill and
   every adopted skill that has local edits.
2. **Compare against the kit catalog.** For each local skill or divergence,
   compare trigger, decisions, inputs/outputs, side effects, stop conditions,
   and verification against the kit's current owner. Ask:
   - Is the behavior generic beyond this target's product nouns?
   - Does it prevent a recurring failure the kit catalog does not cover?
   - Can it be rewritten without project-specific commands, prompts, or secrets?
3. **Draft generalized proposals.** For keepers, draft the smallest
   generalized addition (`IMPROVE_EXISTING`) or a contract only (`NEW_SKILL`).
   Redact private paths, repository URLs, credentials, and product-specific
   examples. Record source project (anonymized if needed), license for the
   contribution, retrieval date, and the exact behavior worth considering.
   Mark `PROJECT_SPECIFIC` when domain assumptions remain necessary.
4. **Propose, do not publish.** Present the evidence table and exact fork/branch
   plan. Stop for explicit approval of the exact scope. Do not create a remote,
   push, or open a pull request unless the user explicitly authorizes that
   external action per `.agents/AGENTS.md`.
5. **Publish only with approval.** On approval, create the fork if needed,
   push the branch with the generalized patch, and open the PR via `gh` using
   `.github/pull_request_template.md`. Include provenance, disposition,
   verification (`make check`), and the matching/neighboring/ambiguous probes.

## Boundaries and gotchas

- Keep provenance honest: do not copy copyrighted prose or bundled assets with
  unclear reuse terms; summarize ideas in original language.
- Run `scripts/public_hygiene_check.py` and `validate_repository.py` over the
  proposed patch before pushing.
- Prefer `IMPROVE_EXISTING` over `NEW_SKILL`; adding a synonymous skill adds
  routing cost without value.
- The maintainer side remains `catalog-discovery` → `skill-reviewer` intake →
  `skill-authoring` + `skill-evaluation` → `make check`. A PR being opened
  does not imply acceptance.

## Report and stop condition

Report the inventory, evidence table, dispositions, redacted generalization,
and fork/branch/PR plan. Stop after the report when approval is missing, when
provenance or license cannot be established, or when the next step would
expose private data. Do not claim a contribution is valuable merely because a
local skill exists.
