---
name: parallel-multi-agent
description: >-
  Split multi-track work into adaptive, bounded concurrent Task subagents when
  file ownership is disjoint. Use when planning large fixes, mixed docs/code
  changes, review fan-out, or when the user asks to parallelize / fan out /
  multi-agent.
---

# Parallel multi-agent playbook

Always-on summary: `.kilo/operating.md` § Parallel multi-agent work. Use this
skill for the full split/integrate workflow.

## Step 1 — Partition

List the smallest useful set of independent tracks as a table. The number of
tracks is task-dependent, not a fixed two-agent recipe; normally use one track
per independent concern, not one agent per file. For a material audit, keep
the fan-out bounded (usually 2–6, maximum 8) and reserve a coupled track for
files that must be reasoned about together.

| Track | Owns (files/dirs) | Risk | Role | Depends on |
| :--- | :--- | :--- | :--- | :--- |
| A | … | … | … | none / track B output |

For review work, add risk, iteration cap, and stop condition. The parent owns
the full diff and final coverage matrix; each worker receives only its assigned
paths and minimum dependencies.

- **Independent** → parallel Task agents (same parent turn).
- **Coupled** → one agent or the parent.

State the delegation plan to the user before the first material or parallel
worker launch and obtain approval unless the user explicitly requested the
named read-only workflow or its instructions authorize bounded discovery.
Treat `subagent_type` as the worker role, not proof of the underlying model.

Use the active harness's native delegation for named read-only workflows only
after explicit approval, with disjoint ownership and a bounded prompt for each
track. Record the actual session or model evidence when the harness exposes
it. If it does not, keep the work parent-owned; never claim that a role label
changed the model.

## Step 2 — Brief each agent

Every worker prompt must include:

1. Absolute repo path + current branch
2. Goal and acceptance criteria
3. Files to edit / files forbidden
4. **Already done** context (so they do not redo or conflict)
5. Project constraints worth repeating (integrity rules, no `latest` tags,
   contract-first, coverage >= 90%, one-language-per-service)
6. Iteration cap and compact output format

Keep prompts and reports bounded. Prefer each delegated request below **128K**
and split it before it approaches **180K**. Give each agent an explicit file
scope, stop condition, and iteration cap; request at most 12 report lines and
5 findings, not raw file dumps or progress logs. Scope the evidence set so the
worker can reserve its final step for the required compact report; a worker
that consumes its entire iteration budget on reads has not completed its
track. Split broad work into staged discovery and focused follow-ups; the
parent retains integration and final verification.

### Required handoff contract

Instruct every worker to return only this compact handoff shape — never full
file contents, raw logs, or giant tool traces:

```text
Track: <Track ID/Name>
Status: SUCCESS | FAILED | PARTIAL
Modified files: <list of exact repo-relative paths>
Summary: <2-3 sentence summary of changes made>
Self-verification: <commands executed and PASS/FAIL status with counts>
Risks/Blockers: <any residual risk or deferred work, or "none">
```

Workers must not perform the whole parent task. They should not receive the
full repository context, run builds or `make` gates, start k3d or servers,
edit files outside their scope, inspect secrets or runtime data, or load
unrelated skills. If a worker approaches its context or iteration limit, it
returns a compact partial report and the parent starts a new narrower
follow-up. Do not use manual compaction as a way to continue the same
oversized worker task.

Independent tracks must launch concurrently, not one foreground task at a
time. Submit all independent Task calls in one message. Foreground waiting is
reserved for coupled work whose next step depends on the result.

## Step 3 — Integrate

1. Read each agent's compact summary; verify diffs with `git status` /
   `git diff`
2. Fix overlap conflicts yourself (do not re-fan the same files)
3. Run gates **serially** (`STRICT=1 make prerequisites`, `STRICT=1 make
    format`, `STRICT=1 make lint`, `STRICT=1 make unit`, `STRICT=1 make
    coverage`, `STRICT=1 make build`); never run concurrent gate or e2e runs
    in one clone — they corrupt each other and fake green
4. Re-run only tracks affected by an edit; add a cross-track verifier only
   when a fix crosses ownership boundaries
 5. Update `docs/implementation-status.md` / skills if behavior or workflows
    changed

### Worker failure and partial triage

When a worker hangs, times out, hits a context/iteration limit, or returns a
broken patch:

1. **Isolate the failure.** Check whether the failed worker's write scope is
   strictly disjoint from other completed tracks. Never discard independent
   successful tracks due to an isolated sibling failure.
2. **Keep partial state clean.** Confirm `PARTIAL`/`FAILED` modifications are
   fully reverted, stashed, or isolated in a separate branch or worktree before
   integrating any green sibling; do not integrate on top of uncommitted
   partial changes.
3. **Integrate green tracks.** Apply and verify all successful disjoint tracks
   through the normal serial gates.
4. **Recover the failed track** with one explicit strategy: re-brief a narrower
   single worker, fall back to serial parent execution, or roll back cleanly
   when it is a blocking hard dependency for other tracks.

## Review-specific fan-out

For adversarial PR review, the parent should first inventory changed paths and
high-risk hunks, then assign focused tracks such as CI/build, integrity-rule
compliance, runtime correctness, contracts/generated code, persistence/
security, and tests/docs/anti-cheating. Use only tracks represented by the
diff. A second model is a targeted verifier for high-risk or disputed
findings, not a reason to send two agents the entire PR.

Prefer the repository's specialized types when available: use
`agent-guidance-auditor` for rules/CI/Kilo guidance,
`docs-contract-auditor` for doc/source contracts, `polyglot-reviewer` for
cross-language convention review, and `explore` for narrow source discovery.
Use `general` only as a last-resort bounded role for a genuinely low-risk,
non-material single scout; it is never a substitute for a specialized track.

Never paste full prior reports into follow-ups; pass only the finding and the
smallest affected path set.

## Worktree and state isolation

Treat a worktree as an isolated code workspace, not a place to duplicate
credentials or runtime state:

- Never copy `.local/`, kubeconfigs, MinIO credentials, `.env`, databases,
  logs, or runtime state into another worktree. Keep configuration
  placeholder-only and use disposable ignored state for tests or local runs.
- Do not use shared `git stash` or autostash across worktrees. The parent owns
  integration, cleanup, and the final serial gate run.

## One gate run at a time

Concurrent agents running `make` gates (especially k3d e2e, coverage, or
builds) in the same clone corrupt each other and fake green results. Pick one:

1. **Parent owns the gates** (simplest): agents edit files and report; only
   the parent runs tests/gates. Tell each agent explicitly not to run `make`.
2. **Worktree per agent**: give each a `git worktree add` directory so each
   gets its own build state and k3d context.

Either way, never trust a green result from a run that overlapped another
agent's build — re-verify serially.

## Repo-specific ownership hints

| Concern | Prefer owner |
| :--- | :--- |
| Contracts / generated models | `contracts/` + `make contracts` — **single** stream; consumers coupled to contract changes |
| Kafka topics / event schemas | Coupled across producer and consumer services; coordinate before parallel work |
| A single service | One stream per service directory; per-language formatters own their files |
| Docs / implementation-status | `docs/**` — safe parallel with service code |
| Agent skills / AGENTS | `.agents/**`, `.kilo/**` — safe parallel with app code |
