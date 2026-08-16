# Agent operating norms

Portable, harness-agnostic operating rules for any coding agent working in this
repository. `AGENTS.md` owns the invariants and task-to-skill index. This file
is a thin Kilo-specific projection of the canonical always-on norms defined in
`.agents/OPERATING.md`; that file remains the source of truth, and this file
should stay aligned with it rather than duplicating it. Deep how-to lives in the
registered skills under `.agents/skills/` and `.kilo/skills/` — prefer a skill
over inventing a parallel workflow.

Harness-specific entrypoints and projections (`CLAUDE.md`, Copilot, Cursor,
Windsurf, and Kilo files) should point to or summarize the canonical rules in
`.agents/OPERATING.md`.

## 1. Prefer project skills

For a task that matches a skill, **read and follow that skill** before
inventing a process. Repository skills take precedence over user-level or
global skills; external material may fill a verified gap but never overrides
project invariants.

When adding or renaming a project skill, update the `AGENTS.md` index. If its
skill root or registration path changes, update the registered `skills.paths`
configuration in the same change.

| User intent | Skill |
| :--- | :--- |
| Implement / resume a milestone | `rghw-milestone` |
| Run gates / evidence before changes | `/quality-gate` command |
| Review working-tree changes before commit | `/review-diff` command |
| Commit / push | `commit-and-push` |
| Open PR | `open-pr` (+ mandatory `adversarial-pr-review`) |
| Adversarial / multi-agent PR review | `adversarial-pr-review` |
| Review a diff or subsystem | `code-review` |
| Artifact-quality / "de-slop" audit | `ai-slop-detector` |
| Docs audit vs source truth | `documentation-review` |
| Incremental docs sync after a change | `docs-sync` |
| Review skills / agent files for content depth | `skill-reviewer` |
| Audit rules/skills structure, overlap, drift | `rules-and-skills-audit` |
| Audit or stage external agent guidance safely | `agent-foundation-audit` |
| Create or modify a skill | `skill-authoring` |
| Fan-out parallel work | `parallel-multi-agent` |
| QA loop / test hardening | `continuous-quality` |
| Broad bounded improvement cycle | `continuous-improvement` |
| Comprehensive read-only quality sweep | `comprehensive-quality-overhaul` |
| Unattended multi-pass cleanup | `autonomous-code-optimizer` |
| TODO burn-down | `todo-resolution` |
| Comment hygiene / explain complex code | `complex-code-comments` |
| Dependency upgrades | `dependency-upgrade` |
| Architecture review / redesign brainstorm | `architecture-review` |
| Code-size reduction / large-file splits | `reduce-code-size` |
| Manual browser interaction QA | `ui-manual-qa` |
| Fast post-deploy UI smoke | `post-deploy-ui-smoke` |
| Refresh committed UI screenshots | `docs-screenshot-refresh` |
| Maintain the end-user guide | `user-guide` |
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

Before material or parallel delegation, define the minimum capability and
disjoint ownership. Record the harness or session evidence actually exposed;
keep the work parent-owned when the harness cannot expose the needed
capability. A worker role or agent label is not evidence of the underlying
model.

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
(k3d port-forwards, `rghw run`, watchers, long sleeps).

1. Start long-lived processes in the background.
2. Wait for readiness with short polls / log patterns, not by awaiting the
   process itself.
3. Poll running processes with SHORT sleeps (5–10s, never 60s+) and post a
   visible one-line progress note in the chat after every poll, so the user
   always sees the run is alive and where it is.
4. If blocked ~15–20s with no useful progress, say what you are waiting on.
5. When done, kill the process and free ports; never leave orphan k3d, Docker,
   Java, or Node processes.
6. Clean up only your own temporary artifacts; preserve `.local/` persistent
   directories.
7. Prefer an exit notification or bounded completion wait when the host supports
   it; do not keep polling a process that has already exited.

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
- Keep source, tests, committed docs, screenshots, and PR artifacts free of
  absolute user paths, machine-specific hostnames, credentials, tokens, and
  account data. Operational docs may use documented loopback placeholders such
  as `localhost`, never personal machine names.
- Resolve deprecation warnings before declaring a change complete. When an
  upstream or toolchain constraint makes resolution impossible, record the
  exact warning, why it cannot be fixed, the mitigation, and the condition
  for revisiting it; do not suppress or ignore it without that record.

## 8. Harness delegation

Use the active coding harness's native worker and delegation controls when the
user authorizes delegation. The parent owns task decomposition, coverage,
triage, integration, and final serial gates. A worker role or agent label is
not evidence of a particular model or independent execution.

Before any material or parallel launch:

1. Define the task profile, minimum capability, and disjoint ownership.
2. Record the harness or session evidence actually exposed, or state that it is
   unknown.
3. Give each worker the repository path, branch, goal, files to touch or avoid,
   acceptance criteria, iteration cap, and compact output format.
4. Keep work parent-owned if the harness cannot expose the needed capability;
   do not silently substitute a role label or provider.

## 9. Context-mode plugin and MCP servers

The project config loads the `context-mode` and `@tarquinen/opencode-dcp`
plugins and local/remote MCP servers; changes to `kilo.json` take effect on
the next Kilo restart.

Active MCP servers:

- `context7` — up-to-date library docs (remote).
- `gh_grep` — GitHub code search (remote).
- `kops` — read-only Kubernetes tools (`k8s_get`, `k8s_describe`, `k8s_logs`,
  `k8s_events`, `k8s_triage`, `k8s_inventory`) against the k3d cluster via
  kubectl; never returns Secret/ConfigMap values. Lives at
  `~/.local/share/kilo/mcp-servers/kops`. **Prefer these tools over raw
  `kubectl`** for read-only cluster inspection (pod state, rollout status,
  logs, events, inventories) — they are idempotent, summarize output, and
  cannot leak Secret/ConfigMap values.

`context-mode` routing — the plugin redirects agent tool calls that would
flood the context window:

- `curl`/`wget` without silent (`-s`) file-output (`-o FILE` / `> FILE`) is
  redirected — use the `ctx_execute` / `ctx_fetch_and_index` tools instead,
  which have full network access and keep raw bodies out of context. Silent
  file-output downloads still pass through.
- Inline HTTP in scripts (`fetch(`, `requests.get(`) is redirected the same way.
- Large shell/filter/analysis work should use `ctx_execute` (sandboxed code,
  only stdout enters context) instead of dumping raw output into the session.
- `ctx_search` queries the plugin's session index; `ctx_index` stores content
  for later search. The plugin persists per-session state under
  `~/.config/kilo/context-mode/`.

`@tarquinen/opencode-dcp` prunes obsolete tool outputs from the conversation
context to keep long sessions small.

## 10. LSP servers

The project config sets `"lsp": false` in `kilo.json`, so this repository does
not request automatic LSP startup or language-server installation. A host may
enable LSP independently, but those diagnostics do not replace the repository's
quality gates or evidence discipline.

This does not replace the repo's evidence discipline: keep captured logs under
`.local/diagnostics/`, redact credentials, and never log plaintext or image
bytes.

## 11. User-visible UI change verification

When editing `services/web-shell`, `services/artifact-inspector-ruby`,
`web/`, HTML/CSS/JavaScript, browser-facing routes, or documented screenshots:

1. For responsive changes, verify fresh captures at phone (about 390px), tablet
   (about 768px), laptop (about 1280px), desktop (about 1440px), and wide (about
   1920px) viewports; use DPR 2 when the capture tool supports it. For a
   non-responsive change, use phone and laptop plus any directly affected width.
2. Use a fresh build or hard refresh and confirm the served assets are current
   before judging styling. Stale CSS or JavaScript is not valid visual evidence.
3. Exercise the changed browser interactions and states, not only unit tests;
   browser behavior can regress while backend tests remain green.
4. Capture fresh screenshots for user-visible changes. Keep throwaway evidence
   under `.local/diagnostics/`; refresh committed documentation screenshots only
   when the canonical presentation changed.
5. Complete the relevant visual and interaction checks before opening a PR. A
   code-only claim is not sufficient for a visual change.
