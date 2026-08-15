---
name: harness-adaptation
description: >-
  Adapt a repository's canonical agent guidance to the capabilities of the
  active coding harness without creating a parallel source of truth. Use when
  adding, reviewing, or diagnosing support for a known or future harness;
  translating instructions or skills across harnesses; or deciding which
  project entrypoints the current harness needs. Inspect and propose by
  default; modify only after the exact adapter plan is approved.
---

# Adapt Guidance to an Agent Harness

Integrate by capability, not by a permanent allowlist of product names. The
active harness and its model determine what they can discover; repository files
remain the durable source of truth.

## Contract

- **Inputs:** repository root, active harness, current repository guidance, and
  the user's intended level of support.
- **Default output:** a capability profile, discovery gaps, the smallest adapter
  plan, verification steps, and an approval gate.
- **Default side effects:** none. Identification and planning are read-only.
- **Apply side effects:** only the approved thin entrypoints, projections,
  metadata, or documentation.
- **Stop conditions:** stop before mutation; stop when the canonical owner,
  instruction precedence, supported skill format, or requested compatibility
  level is materially unclear.

Read [the capability contract](references/capability-contract.md) before
designing an adapter. When this skill is used during initial adoption, follow
the approval and create-only rules in `bootstrap-project` as well.

## Workflow

### 1. Identify the active harness

Use evidence available inside the current session first: harness-provided
context, documented project conventions, installed version output when safe,
and existing repository markers. The agent may state which harness it is
running in; do not introduce a classifier or separate model to infer it.

A user-reported model or profile switch is current session evidence, not a
harness capability change. Do not carry a stale model label from an earlier
turn, ask the user to repeat a switch they already reported, or treat the switch
as broader task authority. Claim an exact model only when the user or harness
exposes it.

Treat environment variables and filenames as clues, not proof. Do not inspect
credentials, account files, telemetry, caches, conversation databases, or
unrelated personal directories.

If the harness cannot be identified, continue with the unknown-harness fallback
instead of guessing a brand.

### 2. Build a capability profile

Determine the current harness's behavior for:

1. instruction discovery paths, scope, precedence, and size limits;
2. reusable skill discovery, format, metadata, and invocation;
3. links, imports, or references to canonical repository files;
4. nested-directory and monorepo behavior;
5. reload or new-session requirements after guidance changes;
6. an observable way to verify instruction and skill discovery.

Prefer the installed harness's own documentation or current primary
documentation. Record unknowns explicitly. Product names and version snapshots
may inform the profile, but they must not become hard gates in the workflow.

### 3. Locate canonical owners

Map each applicable rule to its existing canonical owner. Preserve the target
repository's hierarchy. If no hierarchy exists, prefer:

- one universal, thin repository entrypoint;
- one canonical project rules and routing file;
- one compact always-on operating file;
- focused, task-triggered skills;
- harness files that only point to or narrowly project those owners.

Do not copy full guidance into every harness format. Repeat only a short,
high-risk boundary when a pointer cannot guarantee it will be read.

### 4. Choose the smallest compatible projection

Use the first applicable strategy:

1. **Native discovery:** use canonical files directly when the harness already
   discovers them.
2. **Thin pointer:** add the harness's instruction entrypoint and direct it to
   canonical files.
3. **Narrow projection:** repeat only essential rules when links or imports are
   not followed reliably.
4. **Native skill registration:** expose the existing skill directory through
   a supported project-local path or metadata file without forking its content.
5. **Manual entrypoint:** when persistent project instructions are unsupported
   or unverified, provide a reusable invocation prompt that tells the harness
   exactly what to read.

### Adapter size budget and truncation guardrails

Keep adapter files strictly within harness injection budgets:

- **Size constraint:** Keep root adapter files (`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`) under 40 lines and under 2 KB.
- **Pointer pattern:** Use pointer syntax (e.g. `@AGENTS.md`, `@.agents/AGENTS.md`) rather than copying rules.
- **No full skills in root adapters:** Never copy full skill bodies into always-loaded entrypoints.
- **Truncation check:** If a harness imposes a strict character limit, project only the universal invariants and a pointer to the on-demand skill index.

### Multi-adapter consistency

When a repository contains multiple harness entrypoints:

- Every adapter must delegate to the same canonical source (`.agents/AGENTS.md` and `.agents/OPERATING.md`).
- Never define harness-specific policy overrides that contradict canonical guidance.
- If an existing adapter has diverged (e.g. contains outdated hardcoded rules), propose replacing its body with a standard thin pointer to `.agents/`.

### Rule vs skill projection strategy

| Harness capability | Guidance type | Recommended projection | In-repo example |
| :--- | :--- | :--- | :--- |
| Native skill discovery (e.g. Gemini CLI, Claude Code) | Canonical skills (`.agents/skills/`) | Native directory discovery without file duplication | `GEMINI.md`, `CLAUDE.md` |
| On-demand rule matching (e.g. Cursor `.mdc` with globs) | File-scoped guidance | Thin `.mdc` pointer with glob triggers pointing to canonical skill | — |
| Static always-injected prompt (e.g. Copilot instructions) | Invariants & routing | Compact table index of available skills, loaded only on task match | `.github/copilot-instructions.md` |

Prefer one physical skill owner. Use a supported link only when its behavior is
documented and portable enough for the target; otherwise propose a generated
projection and a drift check.

Before applying a projection, check that its trigger, name, and path do not
collide with another skill or harness entrypoint. Prefer a compact pointer to
the canonical body and keep rare harness-specific detail behind a reference.
Record the source revision and the projection's expected round-trip behavior;
the adapter must not silently become a second source of truth.

### 5. Present the adapter plan

Report:

| Capability | Evidence | Existing owner | Proposed projection | Confidence |
| :--- | :--- | :--- | :--- | :--- |
| instructions, skills, scope, reload, verification | source or observed fact | exact path | exact create/edit | high/medium/low |

List every file to create or edit, repeated safety boundary, unresolved unknown,
and verification action. Separate current observed support from intended or
best-effort support. Stop for approval before changing the target.

### 6. Apply without creating another authority

Make only the approved changes. Keep adapter prose procedural and thin. Point
to canonical owners with repository-relative paths where the harness supports
them. Do not introduce provider routing, model selection, worker supervision,
credentials, automatic downloads, or an updater.

### 7. Verify from the harness boundary

Validate file syntax and links, then follow the harness's documented reload
behavior. Use a fresh task or session when required. Verify discovery with a
small, harmless task that should route to one known skill and ask the harness
to identify the instruction sources it used when that evidence is available.
Also compare the canonical source and projection for drift, body-size limits,
name collisions, and loss of stop conditions or safety boundaries.

File presence alone does not prove discovery. Report each capability as:

- `VERIFIED` — observed in the intended harness and version;
- `DOCUMENTED` — supported by current primary documentation but not exercised;
- `BEST_EFFORT` — projected from generic capabilities with an explicit gap;
- `UNSUPPORTED` — the harness cannot preserve a required behavior.

Record the harness version and verification date in compatibility documentation
when known, but keep bootstrap functional when that snapshot becomes stale.
