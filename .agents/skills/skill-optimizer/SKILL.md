---
name: skill-optimizer
description: >-
  Optimize an agent playbook for lower context cost without weakening routing,
  safety, correctness, or verification. Use when asked to compress, deduplicate,
  rationalize, or reduce guidance; report first and apply only explicitly
  approved findings.
---

# Skill Optimizer

Reduce context cost as a semantic change, not a word-count contest. A shorter
rule that loses a trigger, exception, safety gate, or validation step is a
regression.

## Boundary

- `rules-and-skills-audit` owns structural overlap, conflicts, and drift.
- `skill-reviewer` owns missing content and domain depth.
- `skill-authoring` owns edits after named findings are approved.
- This skill owns measurement, context reduction, and preservation evidence.

Never optimize away safety controls, approval rules, source-of-truth ownership,
distinct routing, or required verification. Keep intentional reinforcement,
different audiences, and thin harness pointers when they improve discovery.

## Workflow

1. Establish the root, branch/status, applicable guidance, and files intentionally
   skipped. Preserve unrelated worktree changes.
2. Run the read-only inventory helper:

   ```text
   python3 .agents/skills/skill-optimizer/scripts/guidance_inventory.py --root . --format markdown
   ```

   It reports lines, words, characters, headings, links, a rough `characters / 4`
   token proxy, and exact repeated prose candidates. Treat the proxy as a
   comparison aid, not a tokenizer result or proof of semantic duplication. Use
   `--scope all` only when related archive material is in scope.
3. Account for the context surface, not only the files in the inventory:
   loaded skills, root instructions, harness projections, tool descriptions,
   linked references, and large generated outputs can all create routing or
   attention cost. Record which surfaces were inspected and which were not.
4. Read the candidates and classify evidence as:
   - exact or near duplication with one clear canonical owner;
   - projection bloat that repeats rather than points to canonical guidance;
   - a progressive-disclosure miss where rare detail can move behind a clear link;
   - routing waste from broad or ambiguous descriptions and indexes;
   - context poisoning, distraction, confusion, or instruction clash that makes
     relevant evidence harder to select or trust;
   - drift or conflict, which is a correctness finding rather than mere savings.
5. For every candidate, record the current owner, replacement owner, exact change,
   estimated removable content, risk, preserved trigger/invariant/exception,
   one matching prompt, one neighboring prompt, one tie-breaker, and checks.
6. Report before editing. Include the baseline, ranked findings, conservative
   savings ranges, keep-separate decisions, skipped files, and a reversible apply
   order. State whether measurements are proxies or tokenizer-verified.
7. Apply only the named findings or bounded group the user explicitly approves.
   Re-run the inventory, inspect the complete diff, and validate routing and
   links after each group through `skill-authoring`.

## Measurement and stop rule

Compare a before/after measure that matches the proposed change: context
tokens or characters, loaded-file count, routing false positives, task output
quality, verification completeness, or evaluation pass rates. A smaller file
is not a success if it causes a safety, ownership, trigger, or verification
regression. Remove optimization machinery that has no measurable benefit, and
stop when the remaining repetition is intentional reinforcement, a distinct
audience projection, or a high-risk rule that must remain visible.

## Approval boundary

No mode or a request to inspect means report-only. Words such as “optimize” or
“apply” do not authorize an unrelated sweep. An explicit implementation request
may authorize only the files and bounded change named by the user; otherwise stop
after the report and ask which findings to apply.

## Progressive disclosure partitioning

When reducing `SKILL.md` size via progressive disclosure, strictly partition content:

- **Must remain in `SKILL.md` (Always Loaded with Skill):**
  - Frontmatter name and routeable description with trigger keywords;
  - Core contract (Input, Output, Owner, Non-goals, Side effects);
  - All non-negotiable safety rules, approval gates, and authorization boundaries;
  - Step-by-step sequential workflow and decision tree;
  - Stop conditions, report shape, and required verification commands.

- **May move to `references/<topic>.md` (Loaded On-Demand):**
  - Deep domain reference manuals, syntax catalogs, and exhaustive API tables;
  - Large illustrative examples, sample outputs, and scenario walkthroughs;
  - Secondary or edge-case troubleshooting runbooks;
  - External intake and provenance audit procedures.

Every extracted reference file must have an explicit, clickable relative link from `SKILL.md` describing exactly when to load it, and must pass link validation during `make check`.

## Context surface prioritization

Prioritize optimizations based on context lifecycle impact:

1. **Tier 1 (Always-On Entrypoints):** `AGENTS.md`, `OPERATING.md`, `CLAUDE.md`, `.cursorrules`. High impact—loaded into every prompt context.
2. **Tier 2 (Harness Projections & System Manifests):** Agent tool descriptions, prompt templates. Medium impact—loaded during tool/agent initialization.
3. **Tier 3 (Conditional Skills):** `.agents/skills/<name>/SKILL.md`. Scoped impact—loaded only when skill triggers.
4. **Tier 4 (On-Demand References):** `references/*.md`. Zero baseline cost—loaded only upon explicit file read.

## Anti-patterns

- deleting repeated text solely because it repeats;
- moving safety invariants, approval gates, or core workflow steps out of `SKILL.md` into reference files;
- applying "telegraphic compression" (stripping syntax and contextual verbs into terse fragments) that increases LLM ambiguity and error rates;
- optimizing Tier 3/4 conditional guidance while leaving high-cost Tier 1 entrypoints bloated;
- replacing a portable rule with an unresolvable or orphaned link;
- treating a frequency report as semantic equivalence;
- moving a high-risk rule behind an optional reference;
- applying a broad mechanical rewrite, commit, publication, or external action
  without explicit authorization.
