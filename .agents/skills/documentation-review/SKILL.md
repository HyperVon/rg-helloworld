---
name: documentation-review
description: >-
  Full documentation audit against source code — finds missing, outdated, and
  incorrect content in README, implementation-status, architecture, runbook,
  ADRs, AGENTS.md, skills, and config, then updates docs to match reality. Use
  when the user asks for a documentation review, docs audit, sync docs with
  code, refresh project docs, or fix stale/wrong documentation.
---

# Full Documentation Review

Perform an end-to-end audit of project documentation against the **current
source code and build config**, then apply corrections. Source of truth is
always the code / Makefile / CI / contracts — never older docs.

This skill is the **full audit**. For incremental "I just shipped X, touch the
relevant docs" work, use [docs-sync](../docs-sync/SKILL.md). For a
**meta-review** of skill structure, coverage, and agent routing
(recommend-only), use [skill-reviewer](../skill-reviewer/SKILL.md).

## Scope (must review)

| Document | Role |
| :--- | :--- |
| `README.md` | Product overview, stack versions, setup, package tree |
| `docs/implementation-status.md` | Authoritative milestone status; must match the current milestone and verification log |
| `docs/architecture.md` | Architecture, integrity rules (§7), milestone order (§29), protocols |
| `docs/runbook.md`, `docs/troubleshooting.md` | Operations commands and failure handling |
| `docs/artifact-lineage.md` | Input IDs and SHA-256 hashes; must match real artifacts |
| `docs/adr/*` | Architecture decision records; must match current decisions |
| `CONTRIBUTING.md`, `SECURITY.md` | Dev setup, PR expectations, security guidance |
| `AGENTS.md` | Invariants, skill index, stack pins |
| `.kilo/operating.md` | Always-on norms; must stay aligned with `AGENTS.md` and skills |
| `CLAUDE.md` | Thin harness entrypoint |
| `.agents/skills/*/SKILL.md` | Domain guidance must match code |
| `versions.env`, per-language build files | Version pins must match |
| `.github/workflows/*` | CI commands/toolchains must match CONTRIBUTING/README/Makefile |

Do **not** invent new marketing docs. Prefer correcting existing files.

## Workflow

Copy this checklist and track progress:

```text
- [ ] Step 0: Inventory code truth
- [ ] Step 1: Audit each doc (missing / wrong / stale)
- [ ] Step 2: Produce findings report
- [ ] Step 3: Apply doc fixes
- [ ] Step 4: Sync agent skills & AGENTS index if needed
- [ ] Step 5: Lint & verify
```

### Step 0: Inventory code truth

Gather facts from code/build (do not trust docs yet):

1. **Versions** — `versions.env`, per-service build files, lockfiles,
   `rust-toolchain.toml`, `global.json`, Helm chart pins.
2. **Architecture** — services under `services/` (one language each), the CLI
   (`cmd/rghw`), `contracts/` definitions, `infra/` (k3d, Terraform,
   PostgreSQL, Kafka, Redis, MinIO).
3. **Protocols** — gRPC/SOAP/HTTP/Kafka/SSE surfaces in `contracts/` and
   `docs/architecture.md`.
4. **Milestones** — `docs/architecture.md` section 29 order vs
   `docs/implementation-status.md` current milestone.
5. **Integrity rules** — `docs/architecture.md` section 7; verify
   docs never contradict them.
6. **Artifact lineage** — `docs/artifact-lineage.md` vs actual artifact
   outputs (input IDs, SHA-256 hashes, maturity ranks).
7. **Tests / anti-cheating** — per-service test suites and
   `tests/anti-cheating/` vs claims in README/AGENTS; coverage gates in
   `Makefile` (`make coverage` = 90% per language).
8. **CI** — `.github/workflows/*`.
9. **Security model** — local-trust assumption; no external runtime APIs.

Use `rg`, package listings, and targeted file reads. Prefer evidence over
memory.

### Parallel audit handoff

For a broad audit with at least two disjoint evidence tracks, use
[parallel-multi-agent](../parallel-multi-agent/SKILL.md) or the active
harness's native read-only delegation after the parent captures a bounded
source/build fact sheet and obtains any required approval:

| Track | Scope |
| :--- | :--- |
| Product / setup | `README.md`, `CONTRIBUTING.md`, `SECURITY.md`, `docs/implementation-status.md` |
| Runtime contracts | `docs/architecture.md`, `docs/runbook.md`, `docs/artifact-lineage.md` |
| Agent guidance | `AGENTS.md`, `.kilo/`, `.agents/`, skill links |
| Build / configuration | `Makefile`, `versions.env`, CI, `infra/`, dependency/tooling claims |

Workers report evidence and paths only; the parent deduplicates findings,
applies edits, runs Mermaid/Markdown/build checks, and owns the final report.
A small or coupled scope may proceed without this handoff.

## Evidence and claims

Treat every material documentation statement as a claim that needs a source:

- Verify behavior against code, build configuration, tests, CI, or safely
  observed behavior. Cite the path, heading, command, or test that supports
  the correction.
- Separate source truth, documented intent, inference, and unresolved
  assumptions. Do not fill a missing fact with plausible wording.
- For external or time-sensitive claims, prefer primary or authoritative
  sources and record the date.
- When documentation, source, and external references contradict one another,
  classify the mismatch, resolve it using the strongest current evidence, and
  record any remaining uncertainty as a gap or deferment.
- Before changing a high-impact safety, dependency, or workflow claim, perform
  a targeted gap check and confirm that the proposed wording does not imply a
  broader guarantee than the repository actually provides.

### Step 1: Audit categories

For every in-scope doc, classify findings:

| Category | Meaning | Action |
| :--- | :--- | :--- |
| **Wrong** | Contradicts code/build | Correct to match code |
| **Stale** | Was true, now outdated (versions, paths, class names) | Update |
| **Missing** | Important behavior exists in code but undocumented | Add concise coverage |
| **Orphan** | Doc describes removed APIs/packages/flags | Remove or rewrite |
| **Skill drift** | `.agents` skill/AGENTS contradicts code | Fix skill or AGENTS |
| **Broken diagram** | Mermaid block fails to render in a viewer | Rewrite to syntax supported by Mermaid 8.x (see below) |
| **Verify snippets/flags** | Code snippets, config samples, CLI commands in docs | Compare flags vs `--help`/arg-parser; mark missing/changed-default flags `WRONG`/`STALE`; match imports/signatures to source |

High-risk mismatch examples:

- Stack versions in README/AGENTS ≠ `versions.env` / build files
- Package tree in README ≠ `services/` layout
- Integrity rules weakened or misquoted in docs
- Milestone order or acceptance conditions out of sync with
  `docs/implementation-status.md`
- Artifact lineage claiming hashes/ranks the pipeline does not produce
- Coverage stated as vague "high" instead of the 90% per-language gate
- CLI flags or Kafka topics documented that do not exist in source
- Lint paths pointing at files that do not exist

#### Mermaid compatibility

GitHub ships a modern Mermaid, but IDE preview panes may still bundle 8.x,
where a diagram that renders on GitHub shows *"Syntax error in graph"*. Keep
every block in `README.md` and `docs/*.md` parseable by 8.x:

- **Quote any label containing non-ASCII or punctuation** — `B{"Deviation ≥ Trigger?"}`, not `B{Deviation ≥ Trigger?}`; unquoted `≥ → × ±` is a lexical error.
- **Use `participant`, not `actor`** in sequence diagrams (`actor` is newer syntax).
- `\n` and `<br/>` both work inside quoted labels; either is fine.

**Link & anchor verification:** every relative file link must resolve to a
tracked repo file from the source doc's directory; every heading anchor
(e.g. `[text](#section-name)`) must match the exact slugified header text in
the target doc. Report links to moved/untracked/deleted files as `BROKEN`.

**Always run the validator** after editing any ```mermaid fence (do not rely
on GitHub preview alone):

```bash
python3 -m venv /tmp/rghello-mermaid
/tmp/rghello-mermaid/bin/pip install -q playwright
/tmp/rghello-mermaid/bin/python .kilo/scripts/validate_mermaid.py
# Optional visual check:
#   .../validate_mermaid.py --render /tmp/mermaid-renders
```

The script downloads/caches Mermaid **8.8.0** and fails if any block does not
parse. Treat a non-zero exit as a **Broken diagram** finding and fix before
declaring the docs review complete. Incremental edits that touch diagrams
should use the same script via [docs-sync](../docs-sync/SKILL.md).

### Step 2: Findings report (before editing)

Classify findings with `UNVERIFIED` when a material claim cannot be confirmed
against current code/build/tests/CI or an authoritative source — record the
missing evidence rather than guessing.

**Risk-based approval gate (before editing):**
- **S** — one directly evidenced wording/link/path correction; apply within
  scope and report.
- **M** — several docs, new section, workflow/compat claim, or broad rewrite;
  present files/claims/evidence/revert shape and wait for approval.
- **High-risk** — Security / privacy / safety / data handling / migrations /
  compatibility guarantees / operational commands: stop for explicit approval
  even if the diff is small, and include focused evidence + compensating
  verification.

Present a short report to the user (or keep as working notes if they asked to
"just fix docs"):

```markdown
# Documentation review

## Summary
N wrong / N stale / N missing / N orphan

## Findings
### [WRONG|STALE|MISSING|ORPHAN] Title
- **Doc**: `path` (section)
- **Evidence**: `code/path` or build fact
- **Fix**: …

## Out of scope / deferred
…
```

If the user only asked to create/run the skill without "fix everything", stop
after the report and ask before applying large edits. If they asked to update
docs, proceed to Step 3.

### Step 3: Apply fixes

Edit docs to match code. Rules:

1. **Prefer minimal diffs** — correct statements; avoid wholesale rewrites
   unless a section is irreparably wrong.
2. **Keep tone** of existing docs.
3. **Cross-link** rather than duplicate.
4. **Docs-sync** — update `docs/implementation-status.md` when user-visible
   behavior changes (see [docs-sync](../docs-sync/SKILL.md)).
5. **Secrets** — never paste real credentials; templates keep placeholders.
6. **Environment agnostic** — no `/Users/...` paths or machine hostnames.

### Step 4: Agent docs coherence

After product docs are fixed:

1. Update `AGENTS.md` stack pins, architecture table, and skill index if a
   new skill was added or invariants changed.
2. Fix any skill that still teaches wrong APIs or commands.
3. Ensure skills/scripts lint the right paths.

### Step 5: Verify

```bash
npx markdownlint-cli AGENTS.md README.md CONTRIBUTING.md SECURITY.md docs/**/*.md .agents/skills/**/*.md .kilo/**/*.md
```

When any Mermaid fence was added or changed (or as part of a full audit):

```bash
/tmp/rghello-mermaid/bin/python .kilo/scripts/validate_mermaid.py
```

Spot-check:

- [ ] README tech stack versions match `versions.env` / build files
- [ ] README directory tree matches `services/` layout
- [ ] implementation-status matches the current milestone and acceptance log
- [ ] Architecture integrity rules match code behavior
- [ ] Artifact lineage matches actual artifact hashes/ranks
- [ ] AGENTS skill index links resolve to existing `SKILL.md` files
- [ ] Every Mermaid block parses under Mermaid 8.x (`validate_mermaid.py` exit 0)

Do not declare complete until markdown lint is clean on touched files.

## Doc ↔ code map (quick reference)

| Topic | Code anchors | Doc anchors |
| :--- | :--- | :--- |
| Milestones | `docs/architecture.md` §29 order | `docs/implementation-status.md` |
| Integrity rules | service boundaries, `cmd/rghw` | `docs/architecture.md` §7, `AGENTS.md` |
| Artifacts / lineage | pipeline outputs | `docs/artifact-lineage.md` |
| Operations | Makefile targets, `infra/` | `docs/runbook.md`, `docs/troubleshooting.md` |
| Dependencies | `versions.env`, lockfiles | `README.md`, `AGENTS.md` |
| Coverage | Makefile `coverage-*` targets | README, `AGENTS.md` |

## Anti-patterns

- Updating docs from memory without opening the cited source file
- Claiming CI coverage without verifying the workflow and gates
- Weakening or misquoting the integrity rules in docs
- Leaving README package trees with removed or renamed services
- Skipping skills when product docs were wrong for the same fact
- Shipping Mermaid that only renders on GitHub (skipping `validate_mermaid.py`
  against 8.x / IDE preview)

## Completion checklist

- [ ] Code inventory completed (versions, services, protocols, milestones, CI)
- [ ] Findings classified (wrong / stale / missing / orphan / skill drift)
- [ ] Product docs updated to match code
- [ ] AGENTS + skills coherent with the same facts
- [ ] `markdownlint-cli` clean on touched markdown
- [ ] Mermaid fences validated with `.kilo/scripts/validate_mermaid.py` when
      diagrams touched
