---
name: complex-code-comments
description: >-
  Audit and update inline comments — add explanations only where code is
  non-obvious or complex, fix inaccurate or stale comments, and remove noise
  that restates the code. Use when the user asks to comment complex code,
  review comments, fix stale/wrong comments, add missing why-comments, or run
  a comment hygiene / complexity-comment pass.
---

# Complex-code comments

Prefer **readable code without comments**. Add or keep comments only where the
code is complex enough that a future reader would otherwise miss intent,
invariants, trade-offs, or non-local consequences.

Always-on writing norms: [.kilo/operating.md](../../../.kilo/operating.md) §
Complex-code comments. This skill is the **full audit / update pass**.

For narrative docs (`README`, `docs/*`), use
[documentation-review](../documentation-review/SKILL.md) instead.

## Principles

1. **Default: no comment** if names, structure, and types make the behavior
   obvious.
2. **Comment the why / invariant / trap**, not the what. Prefer a short
   inline comment above the surprising block over a doc comment that
   paraphrases the signature.
3. **Prefer clarity over commentary** — rename, extract, or simplify first
   when that removes the need for a comment.
4. **Comments are code** — they must stay true. Wrong comments are worse than
   none; delete or rewrite when behavior changes.
5. **Do not comment everything** — a sparse, high-signal pass beats wallpaper.

### Comment when (examples)

| Situation | Comment about |
| :--- | :--- |
| Non-obvious algorithm / formula | Intent, formula, caps, units |
| Order / timing that looks wrong | Why a step runs before another, early-exit |
| Invariant other code relies on | What must remain true (e.g. maturity rank ordering) |
| Surprising edge case | What breaks if skipped |
| Deliberate deviation from "obvious" | Why not the naive approach |
| Cross-cutting protocol semantics | SSE heartbeat framing, Kafka idempotency keys, trace propagation |
| Magic thresholds with domain meaning | What a rank step, hash field, or timeout means here |

### Do not comment when

- Restating the next line (`// increment counter`)
- Narrating getters, DI wiring, trivial CRUD, standard loops
- Duplicating `docs/architecture.md` / skill docs at length — link or point
  briefly
- Apologizing / TODOs that belong in issues (unless a short, actionable TODO)

### Style

- Language-specific: `//` for local why (Go/Kotlin/Java/C++/C#/TS/Rust);
  `#` in Python; doc comments only when the **public contract** is not
  obvious from the signature (units, preconditions, protocol meaning).
- Keep comments tight (usually 1–3 lines). Explain the hard part, not the
  file.
- Match nearby tone; no emoji; no changelog voice inside source.
- Do not invent fake history ("legacy", "temporary") unless verified.

**Good** (from this repo's domain):

```kotlin
// Maturity rank must only increase along the primary path; a re-processed
// artifact keeps its input IDs but must not regress to a lower rank.
```

**Bad**:

```go
// Increment counter
counter++
```

## Scope

| Include | Exclude |
| :--- | :--- |
| `services/**` (all languages), `cmd/`, `libraries/` | Generated / build output (`contracts/` generated models) |
| Complex test helpers / anti-cheating harness | Specs that only assert obvious behavior |
| Non-trivial build logic (Makefile, scripts) | Boilerplate plugin blocks |

**Priority hotspots** (scan first):

- Orchestrator SSE heartbeat and state machine
- Kafka consumer idempotency and retry paths
- Artifact provenance / hash recording
- Maturity-rank transitions
- CLI output boundaries (`cmd/rghello`)
- Protocol boundaries (gRPC/SOAP/HTTP) and trace propagation

## Workflow

Copy and track:

```text
- [ ] Step 0: Choose scope (full repo vs paths)
- [ ] Step 1: Find complex / surprising code without adequate comments
- [ ] Step 2: Audit existing comments (wrong / stale / noisy / missing)
- [ ] Step 3: Apply edits (add / fix / remove)
- [ ] Step 4: Spot-check hotspots against architecture / skills if
      protocols or integrity rules are touched
- [ ] Step 5: Report summary
```

### Step 0: Scope

- Default: full production code across services and the CLI.
- If the user names packages/files, stay in that scope.
- For "everywhere", use the `complex-code-comments` preset of
  `.kilo/model-router/route-subagents` on **disjoint** packages; one owner per
  hot file. The parent owns integration and must not give every worker the
  full repository or use manual compaction to continue an oversized task.

### Step 1: Complexity scan

Walk code looking for blocks a competent reader would not grasp in one pass:
multi-step transformations, rank transitions, retries/backoff, idempotency
keys, protocol framing, "looks redundant but isn't" guards.

For each candidate, decide:

| Verdict | Action |
| :--- | :--- |
| Obvious after rename/extract | Refactor lightly **or** leave; no comment |
| Non-obvious, no comment | Add a short why-comment |
| Non-obvious, weak comment | Rewrite comment |
| Already well explained | Leave |

Do **not** add comments to satisfy a quota.

### Step 2: Existing-comment audit

Classify every comment in scope:

| Category | Meaning | Action |
| :--- | :--- | :--- |
| **Wrong** | Contradicts current code | Fix or delete |
| **Stale** | Refers to removed flags, old thresholds, old names | Fix or delete |
| **Noisy** | Restates obvious code | Delete |
| **Missing** | Complex block with no guidance | Add |
| **OK** | Accurate, necessary | Keep |

Evidence: read the surrounding code. For protocol comments, cross-check
`docs/architecture.md` and domain skills — comments must match **code**, and
if docs disagree with code, fix docs via `documentation-review` (do not "fix"
comments to match stale docs).

### Step 3: Apply

- Edit only comments (and tiny renames that remove the need for a comment)
  unless the user also asked for refactors.
- Keep diffs reviewable; avoid rewriting entire files.
- Do not change protocol or integrity behavior under the guise of commenting.

### Step 4: Verify

- Re-read edited regions: would the comment still help? Still true?
- If protocol/integrity comments changed, skim `docs/architecture.md` for
  consistency.
- Run the per-language formatter on touched files if formatting drifts. Full
  gates only if logic (not just comments) changed.

### Step 5: Report

```markdown
# Complex-code comments

## Scope
…

## Added (missing why)
- `path` — …

## Fixed (wrong / stale)
- `path` — …

## Removed (noisy)
- `path` — …

## Left alone (already clear / intentionally uncommented)
- …
```

## Phrases that should trigger this skill

- "Comment the complex parts"
- "Go through the code and add comments where it's not obvious"
- "Review / fix stale comments"
- "Comment hygiene"
- "Explain the non-trivial logic in place"

## Anti-patterns

- Commenting every function with "Calculate X" doc comments
- Essay comments that belong in `docs/architecture.md`
- Leaving known-wrong comments "for later"
- Parallel agents editing the same file's comments
- Changing thresholds or control flow while "just commenting"
