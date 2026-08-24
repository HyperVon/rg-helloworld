# Agent operating norms

These are the small always-on rules for any coding harness working in this
repository. Task-specific procedure belongs in a matching skill.

## 1. Prefer local guidance

Read repository-local rules and matching skills before inventing a workflow.
Local guidance governs over external or global guidance; use external material
only for uncovered gaps.

## 2. Inspect before changing

Establish the repository state, relevant contracts, source of truth, and user
intent before editing. Preserve unrelated changes and do not infer permission
for commits, publication, external messages, or destructive actions.

Treat the user's newest correction as the current scope and say what prior work
it pauses or supersedes. “Continue” or “proceed” resumes the most recently
stated unfinished scope; it does not authorize unrelated work or external
actions. If a referenced plan or artifact is missing, recover its exact durable
replacement or stop and ask rather than reconstructing new scope from memory.

## 3. Use the smallest applicable skill

Load only the procedure needed for the task. Extend an existing owner skill
when the boundary fits; create a new skill only for a distinct trigger and
workflow.

## 4. Prefer evidence over assumptions

Use current source, tests, build files, configuration, observed behavior, and
primary documentation as evidence. Separate observations, inferences, and
unknowns. Never invent commands, APIs, integrations, or verification results.

## 5. Keep implementations lean and contract-aware

Be defensive at real trust boundaries and confident inside validated contracts.
Avoid speculative abstractions, duplicate validation, silent fallbacks, fake
tests, and wrappers without current policy or transformation value.

## Quality baseline (always on)

Treat “AI slop” as an observable artifact defect, not a guess about authorship:
plausible-looking code, tests, docs, configuration, or guidance that lacks
current evidence or adds unnecessary correctness, maintenance, safety, or
review cost. Apply this lightweight pass to every task:

- Tie non-obvious claims, commands, APIs, configuration, tests, and completion
  statements to current source, contracts, observed behavior, or checks; label
  unknowns instead of filling them with assumptions.
- Before adding an artifact or abstraction, identify its concrete consumer,
  canonical owner, simpler alternative, and outcome-level verification.
- Keep the change and its documentation focused on the requested user or
  maintainer task. Do not add speculative wrappers, duplicate mechanisms,
  misleading tests, or unrelated cleanup.
- Treat style, verbosity, unusual formatting, and formulaic language as prompts
  to investigate, not defects by themselves.

Use `ai-slop-detector` for a scoped evidence-based audit or explicitly
authorized cleanup. The full skill is conditional; this compact baseline is
not. Do not turn ordinary work into a repository-wide audit merely because the
baseline is always active.

## 6. Plan meaningful mutations

For guidance adoption, external content, broad rewrites, or risky changes,
present the exact scope and conflicts before applying. Approval of a plan does
not authorize unrelated operations.

## 7. Verify before completion

Run the smallest useful checks during iteration and the repository's complete
relevant gates before claiming success. State exactly what ran, what passed,
what failed, and what was not run.

## 8. Keep context and output bounded

Search narrowly, summarize large outputs, retain only actionable excerpts, and
store diagnostics outside tracked content. Do not dump secrets, dependency
trees, full logs, or unrelated files into prompts or reports.

For a session handoff, preserve a compact objective, current state, exact next
step, authority, and stop conditions. Do not replay the full history or assume
that stale session labels are current.

## 9. Parallelize only independent work

Use the active harness's native delegation capabilities when the user authorizes
delegation. Give workers disjoint ownership, bounded context, explicit stop
conditions, and no secret access. Treat current user or harness evidence about
session state as authoritative; session changes do not broaden task authority.
The parent owns integration and final checks.

## 10. Leave a clean, recoverable state

Do not leave servers, watchers, temporary files, worktrees, or child workers
running after they are no longer needed. Never share credentials or application
state between worktrees. Keep public tracked files free of personal and secret
data.

Distinguish disposable execution artifacts from continuation artifacts. A plan,
handoff, or PR body that the user may reference later needs a durable location
or a named durable replacement before its temporary copy is removed.

## 11. No blocking long processes

Do not leave the user waiting on a foreground command that never exits (k3d
port-forwards, `rghw run`, watchers, long sleeps). Start long-lived processes
in the background; wait for readiness with short polls or log patterns rather
than awaiting the process itself. Poll with short sleeps (5–10s, never 60s+)
and post a visible one-line progress note after every poll. If blocked for
~15–20s with no useful progress, say what you are waiting on. When done, kill
the process and free its ports; never leave orphan k3d, Docker, Java, or Node
processes behind.

## 12. Verify user-visible UI changes

When editing `services/web-shell`, `services/artifact-inspector-ruby`, `web/`,
HTML/CSS/JavaScript, browser-facing routes, or documented screenshots:

1. For responsive changes, verify fresh captures at phone (~390px), tablet
   (~768px), laptop (~1280px), desktop (~1440px), and wide (~1920px)
   viewports, using device pixel ratio 2 when the capture tool supports it.
   For a non-responsive change, phone and laptop plus any directly affected
   width are enough.
2. Use a fresh build or hard refresh and confirm the served assets are current
   before judging styling — stale CSS or JavaScript is not valid evidence.
3. Exercise the changed browser interactions and states, not only unit tests;
   browser behavior can regress while backend tests stay green.
4. Capture fresh screenshots for user-visible changes. Keep throwaway evidence
   under `.local/diagnostics/`; refresh committed documentation screenshots
   only when the canonical presentation changed.
5. Complete these visual and interaction checks before opening a PR; a
   code-only claim is not sufficient for a visual change.
