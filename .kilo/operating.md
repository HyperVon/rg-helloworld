# Kilo operating projection

This file is the Kilo-specific projection of the canonical always-on norms in
[`.agents/OPERATING.md`](../.agents/OPERATING.md). That file is the source of
truth — read and follow it. `AGENTS.md` owns the invariants and the
task-to-skill index; deep how-to lives in the registered skills under
`.agents/skills/` and `.kilo/skills/`. This file only adds what is specific to
the Kilo harness configuration in this repository.

## Canonical sections (summary — read the canonical file for detail)

1. Prefer project skills over inventing a workflow; update the `AGENTS.md`
   index when adding or renaming skills.
2. Complete every PR test-plan item before `gh pr create`; never defer checks
   to after merge.
3. Parallel multi-agent work only across disjoint files; one `make` gate run
   at a time; never share `.local/`, kubeconfigs, or credentials between
   worktrees; parent owns integration and final serial gates.
4. No blocking long processes (canonical §11): background long-lived
   processes, short polls with visible progress notes, kill orphans when done.
5. Complex-code comments only where logic is non-obvious.
6. Lean, contract-aware code: defensive at trust boundaries only; no
   impossible-case tests or coverage padding.
7. Evidence discipline: source/tests are truth; quiet test modes; complete
   logs under `.local/diagnostics/`; redact credentials and personal paths;
   resolve deprecation warnings before completion.
8. Harness delegation: parent owns decomposition, triage, integration, final
   gates; worker labels are not evidence of model capability.
9. Verify user-visible UI changes before opening a PR (canonical §12).

## Kilo-specific configuration facts

- The `context-mode` plugin redirects context-flooding tool calls: bare
  `curl`/`wget` and inline `fetch(`/`requests.get(` go to the sandboxed
  `ctx_execute` / `ctx_fetch_and_index` tools instead (silent `-o FILE`
  downloads pass through). Query stored content with `ctx_search`; stage new
  content with `ctx_index`.
- The `@tarquinen/opencode-dcp` plugin prunes obsolete tool outputs from long
  sessions.
- Prefer the `kops` MCP tools (`k8s_get`, `k8s_describe`, `k8s_logs`,
  `k8s_events`, `k8s_triage`, `k8s_inventory`) over raw `kubectl` for
  read-only cluster inspection; they summarize output and cannot return
  Secret/ConfigMap values.
- `context7` serves current library docs; `gh_grep` searches GitHub code.
- `"lsp": false` is set in `kilo.json`: this repository does not request
  automatic LSP startup; host-side LSP diagnostics do not replace the
  repository's quality gates.
- Changes to `kilo.json` take effect on the next Kilo restart.

## Session hygiene

Work in small increments; compact long sessions before large generation steps.
On resume after compression, rely on `docs/implementation-status.md` and the
`rghw-milestone` skill rather than replaying transcripts. Never dump full file
contents or command output into a prompt.
