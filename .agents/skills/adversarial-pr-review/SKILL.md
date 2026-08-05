---
name: adversarial-pr-review
description: >-
  Parent-orchestrated adaptive adversarial PR review — partitions a PR into N
  bounded read-only reviewer tracks based on file ownership and risk, validates
  findings in the parent, and re-reviews only affected tracks until
  convergence. Use when creating a PR, updating an open PR, or when the user
  requests an adversarial or multi-model PR review.
---

# Adversarial PR review (local)

**Local only** — runs inside the current agent session. A bare `git push` does
not run it.

## When this skill is mandatory

Read and follow this skill **before finishing** any of:

1. **Open PR** — after quality gates, before `gh pr create`
   ([open-pr](../open-pr/SKILL.md)).
2. **Update open PR** — when [commit-and-push](../commit-and-push/SKILL.md)
   (or equivalent) will push to a branch that already has an open PR.
3. **Explicit ask** — when the user requests adversarial or multi-agent review
   of a PR or branch diff.

If the branch has no open PR and the user is only committing WIP without
opening one, skip this skill unless they asked for a review.

## Core operating model

This is a **parent-orchestrated review**, not a request for every subagent to
review the entire repository. The parent agent owns the review plan, merge
base, coverage matrix, triage, edits, quality gates, and final convergence
decision. Task agents are bounded read-only scouts or focused verifiers.

### Select N tracks from the change

`N` is deliberately not a fixed number. After inspecting the changed-file list
and high-risk hunks, the parent chooses the smallest useful set of independent
tracks. As a guide, a material PR normally uses **2–6 tracks**, with a hard
maximum of **8**; a tiny one-concern change may use one track when the parent
records why. Do not create one agent per file and do not duplicate a full-diff
review merely to satisfy a count.

Use only tracks represented by the diff. Typical tracks:

| Track | Review question | Typical scope |
| :--- | :--- | :--- |
| CI / build / tooling | Can the workflows, toolchain, and gates run as claimed? | `.github/`, `Makefile`, scripts, configs, `versions.env` |
| Integrity rules | Do the 10 integrity rules hold? No plaintext/expected-character fields downstream of glyph planning; maturity ranks only increase; artifacts record input IDs and SHA-256 hashes; Kafka consumers idempotent | Changed services plus `docs/architecture.md` §7 |
| Runtime correctness | Did behavior, state transitions, or error handling regress in the touched services? | Changed production modules plus named dependencies |
| Contracts / generated code | Does the change stay contract-first? Generated code regenerated and not hand-edited? | `contracts/`, `make contracts` output, consumers |
| Persistence / security | Are credentials, schemas, migrations, permissions, MinIO payload rules safe? | Persistence, config, security, infra |
| Tests / docs / anti-cheating | Do tests protect the change, coverage stays >= 90%, and the anti-cheating suite still pass? | Changed tests, `tests/anti-cheating/`, docs, skills |

Tracks must have disjoint primary ownership where possible. Add a second,
independent verifier only for a high-risk or disputed track; give that verifier
the finding and the smallest affected path set, not the original full prompt.

Before launching, write a compact parent-side matrix:

| Track | Files / hunks | Risk | Role | Depends on | Stop condition |
| :--- | :--- | :--- | :--- | :--- | :--- |
| … | … | low / medium / high | … | none / track … | … |

## Context and delegation guardrails

These rules are mandatory because a stalled near-limit subagent is worse than
several small, independently useful reports:

- Give each agent an explicit file set and only the minimum source paths needed
  to verify those files. The parent may inspect the full diff; workers should
  not receive it by default.
- Target each delegated request well below the model's practical context
  limit. Prefer prompts and source scopes below about **128K**; split the
  track before it approaches **180K**.
- Cap discovery agents at **8 tool iterations** unless the parent explicitly
  widens the cap for a named high-risk question.
- Require a final report of at most **12 lines** and at most **5 findings**.
  Reports contain findings only, not progress logs, raw file dumps, repeated
  prompts, or a complete transcript.
- Tell agents not to load unrelated skills, run builds or `make` targets,
  start servers or k3d, edit, inspect credentials, read runtime
  data/kubernetes state, or perform the parent's integration work.
- If a worker approaches its context or iteration limit, it must stop and
  return a compact partial report with uncovered paths. It must **not**
  attempt manual compaction and continue in the same task. The parent launches
  a new, narrower follow-up for only the uncovered paths.
- Never paste full prior reports into a follow-up. Pass only the relevant
  finding, path, source line, and one verification question.
- The parent owns all builds and final quality gates. Never run concurrent
  `make` gate runs in the same clone — they corrupt each other and fake green.
  Run gates serially.

## Agent selection and launch

Use the repository's read-only agent roles when they match the track:

| Agent type / capability | Use when |
| :--- | :--- |
| `agent-guidance-auditor` | Rules, skills, CI, `kilo.json`, permissions, and harness guidance |
| `docs-contract-auditor` | Docs checked against source/build/test truth |
| `explore` | Narrow source discovery or evidence lookup |
| `polyglot-reviewer` | Cross-language correctness and repo-convention review |
| `general` | Only when no closer specialized type is available, as a last-resort bounded role |

A generic role is never a substitute for a specialized track and cannot
authorize a material or parallel launch when no suitable role exists. If no
specialized role is available, keep the track parent-owned.

Before launching any material or parallel review track, state the plan to the
user and obtain explicit approval. Record the track, role, scope, and any
substitution. Do not claim that a role label changed the model.

For explicit cross-provider routing, the optional
`.kilo/model-router/route-subagents --workflow adversarial-pr-review --run`
launcher plans one exact provider/model route per track and launches read-only
workers from temporary repository copies; inspect its route report before
claiming independent-model diversity (see
`.kilo/model-router/instructions.md`). If no usable route is available, keep
the review parent-owned and state the limitation.

A prompt must contain:

1. Absolute repository path, branch, and base.
2. The single track question and exact allowed paths or hunks.
3. The PR intent and already-completed context.
4. Forbidden files/actions, especially secrets, kubeconfigs, and runtime data.
5. Acceptance criteria, iteration cap, and the compact output format.

Capture the bounded surface before reviewing the full diff:

```bash
./.agents/skills/adversarial-pr-review/scripts/review_surface.sh main
```

This reports merge-base, diff statistics, and changed paths without launching
agents or reading runtime data. Equivalent inline:

```bash
git diff --stat "$(git merge-base HEAD origin/main)"...HEAD
git diff --name-only "$(git merge-base HEAD origin/main)"...HEAD
```

### Automatic fallback on launch failure

Recover autonomously when an intended role fails, is cancelled, or is
unavailable:

1. Retry once only when the failure appears transient.
2. Otherwise use only a fallback role for the **same narrow track**. A
   different role label alone is not a valid fallback. Do not send the
   replacement the full PR diff.
3. If no suitable fallback exists, stop fan-out and have the parent cover
   **every uncovered acceptance criterion** with sequential checks or keep the
   track explicitly deferred. The track cannot be marked complete while its
   coverage matrix has unchecked paths or questions.
4. Record the requested role, actual role, scope, and the reason for any
   substitution in the verification notes.

## Scope and evidence

The parent review surface is the complete PR change against its merge base,
including intentional behavior changes. Each worker sees only its assigned
slice plus minimum dependencies. Agents must:

- cross-check claims against current source, tests, configuration, or the
  architecture document;
- distinguish a concrete regression from a pre-existing defect or preference;
- flag correctness, safety, persistence, layering, dead-code,
  tautological-test, integrity-rule, and docs/source contradictions in the
  assigned slice;
- verify protocol claims (Kafka topics, SSE framing, gRPC/SOAP surfaces,
  artifact maturity ranks) against `contracts/` and `docs/architecture.md`;
- remain read-only and avoid `make`, k3d, servers, application data, and
  secrets.

Use this output format and nothing more:

```text
track: <name>
critical: No legitimate findings | <path:line> - <evidence, impact, smallest fix>
warning: No legitimate findings | <path:line> - <evidence, impact, smallest fix>
nit: No legitimate findings | <path:line> - <evidence, impact, smallest fix>
coverage: <checked paths>; <uncovered paths or none>
```

## Adaptive convergence loop

Repeat only for affected tracks:

1. **Inventory** — the parent captures the merge base, changed paths, risk
   areas, and the track matrix.
2. **Fan out** — launch N bounded, read-only tracks in parallel when
   independent.
3. **Triage** — the parent verifies each finding against source and removes
   duplicates, false positives, and style preferences that contradict project
   conventions.
4. **Targeted verification** — disputed or high-impact findings get a focused
   second verifier. It receives only the finding and affected paths.
5. **Fix** — the parent applies legitimate critical/warning fixes and small
   clear nits, then runs the required quality gates serially.
6. **Re-review** — re-run only tracks whose paths or dependent contracts
   changed. Add a cross-track verifier only when the fix crosses ownership
   boundaries.
7. **Converge** — every track has a final compact report, all changed
   high-risk paths are covered, and no legitimate critical/warning finding
   remains.

Cap the overall loop at **5 rounds** and each track at **3 review passes**. If
the same disputed finding survives two safe-fix attempts, document the
evidence and explicit deferral instead of thrashing. Nits do not block
shipping unless the user requested polish.

## After convergence

- Commit and push review fixes on the current PR branch when the workflow
  includes commit/push or the user asked for it.
- Summarize the number of tracks, scopes, substitutions, findings fixed,
  deferred items, and quality gates.
- Continue [open-pr](../open-pr/SKILL.md) or finish
  [commit-and-push](../commit-and-push/SKILL.md).

## Checklist

- [ ] Trigger matched: new PR, push to open PR, or explicit review request
- [ ] Parent created an N-track coverage matrix; N was justified by the diff
- [ ] Each agent had a bounded scope, stop condition, and compact output cap
- [ ] Independent tracks ran in parallel where safe; no overlapping `make` runs
- [ ] Failed agents were replaced with narrower scoped fallbacks and recorded
- [ ] Full PR surface is covered across tracks, without every agent rereading it
- [ ] Integrity rules and protocol claims verified against architecture/contracts
- [ ] Legitimate critical/warning findings were fixed and affected tracks re-reviewed
- [ ] Converged or explicitly deferred; no infinite loop or manual-compaction continuation
