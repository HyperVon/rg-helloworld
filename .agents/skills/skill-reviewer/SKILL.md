---
name: skill-reviewer
description: >-
  Reviews agent skills, AGENTS.md, and operating norms — then recommends
  substantive content upgrades (coding standards, architecture guidance,
  domain patterns, anti-patterns, checklists) plus meta fixes (routing,
  indexes, drift). Use when the user asks for a skill review, enhance skills,
  deepen agent guidance, agent-files audit, or meta-review of workflows.
  Recommend only; do not edit unless asked. Default focus is content
  enrichment, not index polish.
---

# Skill / Agent-Files Reviewer

Act as a **staff engineer improving the agent playbook**. Primary job:
recommend **concrete content to add** to skills so future agents write better
code and make better architecture choices. Secondary job: meta health
(indexes, routing, drift, token waste).

This skill is **recommend-only**. Do **not** edit skills / rules / `AGENTS.md`
unless the user asks.

## Review modes

| Mode | When | Output weight |
| :--- | :--- | :--- |
| **`content`** (default) | "Enhance skills", "add more guidance", first full review | ≥70% findings = draft content to add |
| **`meta`** | "Index drift", "routing only", prefer-table sync | Structure / discoverability only |
| **`full`** | Explicit "full scope" / "everything" | Content + meta; content still leads |

If the user does not name a mode, use **`content`**. Do **not** ship a report
that is mostly index polish when they asked to enhance skills.

## How this differs from nearby skills

| Skill | Role |
| :--- | :--- |
| **skill-reviewer** (this) | Recommend **better skill text** (and meta health) |
| [documentation-review](../documentation-review/SKILL.md) | Make docs/skills **match code** (factual sync); applies fixes |
| [ai-slop-detector](../ai-slop-detector/SKILL.md) | Evidence-backed artifact audit across code/docs/skills |
| [rules-and-skills-audit](../rules-and-skills-audit/SKILL.md) | Structural consolidation, not content depth |
| [continuous-quality](../continuous-quality/SKILL.md) | May implement approved skill-content findings later |

documentation-review asks "is this true?" — this skill asks "what else should
agents be taught?"

## Scope

| Path | Role |
| :--- | :--- |
| `.agents/skills/*/SKILL.md` (+ siblings one level deep) | **Primary** — content to deepen |
| `AGENTS.md` | Invariants / index (keep thin; push how-to into skills) |
| `.kilo/operating.md` | Always-on norms; meta sync |
| `CLAUDE.md` | Thin stub only |

Default content targets (highest leverage):

- `rghello-milestone`, `adversarial-pr-review`, `ai-slop-detector`
- `documentation-review`, `docs-sync`, `parallel-multi-agent`
- `continuous-quality`, `autonomous-code-optimizer`, `complex-code-comments`

Process skills still get content ideas when thin — but coding/architecture
skills come first.

## Stance

1. **Teach the agent something it would not invent.** Prefer project-specific
   patterns, traps, and decision rules over generic "write clean code."
2. **Ground in this repo.** Propose additions that match (or deliberately
   improve) how *this* codebase works — the integrity rules, maturity ranks,
   contract-first generation, Kafka idempotency, k3d acceptance. Spot-read
   code when unsure.
3. **Draft the text.** Every content finding includes a **ready-to-paste**
   bullet list, checklist items, or short section — not "consider documenting
   X."
4. **Progressive disclosure.** If a skill would exceed ~500 lines, recommend a
   sibling `reference.md` / `patterns.md` rather than stuffing SKILL.md.
5. **No recommendation theater.** Skip synonym tweaks, emoji, and "add more
   adjectives." Skip meta findings unless mode is `meta`/`full` or they are
   P0/P1.
6. **Praise what works.** Note strong sections so we do not rewrite them.

## Workflow

```text
- [ ] Step 0: Mode (content | meta | full) + scope
- [ ] Step 1: Light inventory (orphans/ghosts only if meta/full)
- [ ] Step 2: Content enrichment pass (PRIMARY)
- [ ] Step 3: Meta pass (if meta/full)
- [ ] Step 4: Filter, severity, draft text
- [ ] Step 5: Report; stop for picks
```

### Step 2: Content enrichment (PRIMARY)

For each in-scope skill, read the skill, then ask:

> If a strong mid-level engineer followed only this skill, what **coding or
> architecture mistakes** would they still make in this repo — and what
> **concrete guidance** should we add?

Mine ideas from:

1. **Code that the skill owns** — patterns, invariants, sharp edges in the
   services named in the skill description.
2. **Tests / anti-cheating suite** — edge cases already proven that the skill
   never mentions.
3. **AGENTS.md / architecture.md** — non-negotiables that should be actionable
   checklists inside the owning skill (not duplicated essays).
4. **Known agent failure modes** — leaking plaintext downstream, skipping
   maturity-rank or hash-provenance fields, using `latest` tags, bypassing a
   required protocol, combining service languages, non-idempotent Kafka
   consumers, mirror tests.
5. **Industry-solid practices that fit** — only when they clearly apply
   (e.g. fail-closed transformation paths, contract-first boundaries, pure
   domain vs I/O).

#### Content lenses (use on coding/architecture skills)

| Lens | Example asks |
| :--- | :--- |
| **Architecture / boundaries** | Wrong layer owns protocol I/O? Missing "do not call X from Y"? Module seam undocumented? |
| **Correctness / safety** | Fail-closed paths? Idempotency? Artifact hashes? Maturity ranks? |
| **API / concurrency** | Kafka consumer semantics, retries, SSE heartbeat framing, cancellation? |
| **Persistence** | Transaction scope, cascade, upsert keys, MinIO large-payload rules? |
| **Testing** | Coverage 90%+, golden artifacts, anti-cheating guards, property/edge cases? |
| **Security / trust** | Secrets, kubeconfigs, local-trust assumptions, logging plaintext? |
| **Readability / craft** | Prefer expressions the codebase already uses; warn against local anti-patterns |
| **Operability** | Logging fields, trace propagation, deterministic outputs, rate-limit behavior under load? |

#### Good vs bad content findings

**Good (do this):**

```markdown
- **[CR-ARCH-1] Add "do not" bullets to rghello-milestone** — §Integrity
  - Gap: Agents still put expected-character fields in downstream events.
  - Draft add:
    - No `targetText`, `expectedCharacter`, `unicodeCodePoint`, or
      `characterName` in any event below the glyph catalog.
    - The CLI prints only the orchestrator terminal `assembledText`.
```

**Bad (avoid):**

- "Improve the integrity section."
- "Add more best practices."
- "Consider mentioning Clean Architecture."

### Step 3: Meta (secondary; required for `meta`/`full`)

Inventory orphans/ghosts; operating-norm drift; weak descriptions; prefer
table; workflow chains; token bloat. Cap meta noise: only P0/P1 or clearly
actionable P2 in `full` mode.

### Severity

| Sev | Meaning |
| :--- | :--- |
| **P0** | Missing guidance that can cause integrity-rule violations or skipped safety gates |
| **P1** | High-leverage coding/architecture gap agents hit often; or broken routing |
| **P2** | Valuable pattern / checklist / anti-pattern worth adding |
| **P3** | Optional depth, examples, progressive-disclosure splits |

## Output

### Required report shape

```markdown
# Agent skills review — YYYY-MM-DD (mode: content|meta|full)

## Verdict
[2–4 sentences; lead with content themes]

## Keep as-is
- …

## Content additions (primary)
### P0 / P1 / P2 / P3
- **[id] Title** — `path` §section
  - Gap: what agents still get wrong
  - Why it matters: …
  - Draft add: (bullets / checklist / short subsection — paste-ready)
  - Optional: sibling file if SKILL.md would bloat

## Meta / structure (secondary; omit in pure content mode if empty)
…

## Proposed new skills (rare)
| Name | Trigger | Why not fold into existing |

## Suggested apply order
1. …
```

### Backlog file

When there are many findings, write paste-ready drafts to a durable file
(e.g. `.agents/skill-content-backlog.md`), not only chat. After the user
applies findings, mark applied items done — do not leave drafts only in
conversation history.

## After approval

1. Paste approved drafts into the named skills (or new sibling refs).
2. Keep indexes in sync only if you added skills or intents.
3. Lint the touched guidance with the repository's markdown lint path.
4. Commit/PR only if the user asks
   ([commit-and-push](../commit-and-push/SKILL.md) /
   [open-pr](../open-pr/SKILL.md)).

## Anti-patterns

- Shipping a **meta-only** report when the user wanted richer skill content
- Vague "improve X" with no paste-ready draft
- Generic textbook advice that ignores this repo's integrity/milestone rules
- Duplicating long architecture essays into every skill (link + checklist)
- Inflating SKILL.md past ~500 lines instead of a sibling reference
- Implementing without approval
- Treating documentation-review's factual sync as a substitute for teaching
  gaps
