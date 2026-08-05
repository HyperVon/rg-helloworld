# Agent operating norms

Portable, harness-agnostic operating rules for any coding agent working in this
repository. `AGENTS.md` is the thin invariants file; this file owns the
always-on norms. Deep how-to lives in skills under `.kilo/skills/` — prefer a
skill over inventing a parallel workflow.

## 1. Prefer project skills

For a task that matches a skill, **read and follow that skill** before
inventing a process. Repository skills take precedence over user-level or
global skills; external material may fill a verified gap but never overrides
project invariants.

| User intent | Skill |
| :--- | :--- |
| Implement / resume a milestone | `rghello-milestone` |
| Run gates / evidence before changes | `/quality-gate` command |
| Review working-tree changes before commit | `/review-diff` command |
| Commit / push | `commit-and-push` |
| Open PR | `open-pr` (+ mandatory `adversarial-pr-review`) |
| Adversarial / multi-agent PR review | `adversarial-pr-review` |
| Artifact-quality / "de-slop" audit | `ai-slop-detector` |
| Docs audit vs source truth | `documentation-review` |
| Incremental docs sync after a change | `docs-sync` |
| Review skills / agent files for content depth | `skill-reviewer` |
| Audit rules/skills structure, overlap, drift | `rules-and-skills-audit` |
| Create or modify a skill | `skill-authoring` |
| Fan-out parallel work | `parallel-multi-agent` |
| QA loop / test hardening | `continuous-quality` |
| Unattended multi-pass cleanup | `autonomous-code-optimizer` |
| TODO burn-down | `todo-resolution` |
| Comment hygiene / explain complex code | `complex-code-comments` |
| Dependency upgrades | `dependency-upgrade` |
| Architecture review / redesign brainstorm | `architecture-review` |
| Code-size reduction / large-file splits | `reduce-code-size` |
| Boot the acceptance stack and verify | `/acceptance-smoke` command |

If no skill fits, proceed normally. Never skip quality gates a skill names.

## 2. Complete verifications before opening a PR

- Every item in a PR test plan must be **executed and checked `[x]` before**
  `gh pr create` (see `open-pr`). Do not defer spot-checks, e2e runs, or
  anti-cheating suites to "after merge".
- Do not open a PR with unchecked boxes; omit or mark N/A with a reason.
- Automated gates alone are not enough when the change needs k3d/e2e or
  cross-service verification; run those first.

## 3. Parallel multi-agent work

Parallelize only when workstreams touch **disjoint files**, each has a
self-contained goal, and the parent can integrate results. One coupled track
for shared files; fan out the rest together in a single parallel message.

- Give each worker: repo path, branch, goal, files to touch/avoid,
  already-done context, acceptance criteria, iteration cap, and a compact
  output format (at most 12 lines / 5 findings).
- Keep delegated prompts below ~128K context; split before ~180K. A worker
  that approaches its limit returns a compact partial report; do not continue
  the same oversized task via manual compaction.
- **One `make` gate run at a time.** Concurrent full gate runs in one clone
  (k3d e2e, coverage, builds) corrupt each other and fake green. Either the
  parent runs all gates serially, or each agent gets its own `git worktree`.
- Never copy `.local/`, kubeconfigs, MinIO credentials, `.env`, databases, or
  runtime state between worktrees. The parent owns integration, cleanup, and
  the final serial gate run. Never trust a green result from a run that
  overlapped another agent's build — re-verify serially.
- The parent owns the coverage matrix, triage, integration, and final
  verification; workers are bounded scouts, not alternate project owners.

## 4. No blocking long processes

Do not leave the user waiting on a foreground command that never exits
(k3d port-forwards, `rghello run`, watchers, long sleeps).

1. Start long-lived processes in the background.
2. Wait for readiness with short polls / log patterns, not by awaiting the
   process itself.
3. If blocked ~15–20s with no useful progress, say what you are waiting on.
4. When done, kill the process and free ports; never leave orphan k3d, Docker,
   Java, or Node processes.
5. Clean up only your own temporary artifacts; preserve `.local/` persistent
   directories.

## 5. Complex-code comments

Prefer readable code without comments. Add comments only where logic is
non-obvious (intent, invariants, traps, non-local consequences). Rename or
extract instead of commenting when that makes code clear. If behavior changes,
update or delete nearby comments — stale comments are worse than none. For a
full comment audit use `complex-code-comments`.

## 6. Lean, contract-aware code

Write code a staff engineer would sign: defensive exactly at trust boundaries
(external protocols, Kafka/Redis, config, artifact provenance), lean and
confident inside them.

- No guards for states the type system or caller contract makes impossible.
- Validate each invariant once, at its owning boundary. Never fall back
  silently over a state that should fail hard.
- Each test kills a distinct defect class; skip impossible-case tests,
  coverage padding, and "does not throw" assertions.
- Prefer the existing local pattern over a new abstraction; a wrapper or
  interface needs a current seam, not a hypothetical one.

## 7. Evidence discipline

- Source, `contracts/`, Makefile, and tests are truth — never older docs.
- Every output artifact records input IDs and SHA-256 hashes; verify claims
  against the artifact lineage (`docs/artifact-lineage.md`).
- Use quiet test modes; capture complete logs under `.local/diagnostics/`.
- Show only relevant failure excerpts; bounded `head`/`grep`/`kubectl logs
  --tail`. Summarize instead of dumping thousands of lines.
- Redact credentials, tokens, hostnames, and personal paths from output.
- Never log the requested plaintext, image bytes, or huge payloads.

## 8. Model selection and routed delegation

The session's default model comes from the host or `kilo.json`; treat it as
the default for ordinary work. Sessions on the free tier have a small output
cap — keep prompts and delegated briefs bounded, and escalate to a capable
route for high-risk or reasoning-heavy work instead of letting a long task
hit its output limit.

For explicit cross-provider model selection, the optional launcher
`.kilo/model-router/route-kilo` discovers provider routes, ranks them by
capability, effective cost, and quota, and starts `kilo run` with an exact
`provider/model` route. For bounded parallel discovery or review tracks, use
`.kilo/model-router/route-subagents --workflow <preset> --run`, which plans
one exact route per track and launches read-only workers from temporary
repository copies. See `.kilo/model-router/instructions.md` for the full
launch contract, presets, and report format.

- Route selection is optional infrastructure, never a substitute for the
  parent-owned coverage matrix, triage, integration, and serial gate runs.
- A role or agent label is not evidence of a model; only an exact route from
  the launcher report is. For adversarial review, inspect the route report
  before claiming independent-model diversity.
- Treat catalog status or configured credentials as insufficient proof of
  live quota; the launcher persists only secret-free cooldown metadata.
- When no usable route is available, keep the work parent-owned and state the
  limitation; do not claim a role-only Task call changed the model.
- Never persist credentials, balances, or raw provider errors in repository
  files; `env.local` and `manifest.local` are git-ignored.
