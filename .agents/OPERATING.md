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
