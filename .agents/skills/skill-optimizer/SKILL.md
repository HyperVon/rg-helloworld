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
3. Read the candidates and classify evidence as:
   - exact or near duplication with one clear canonical owner;
   - projection bloat that repeats rather than points to canonical guidance;
   - a progressive-disclosure miss where rare detail can move behind a clear link;
   - routing waste from broad or ambiguous descriptions and indexes;
   - drift or conflict, which is a correctness finding rather than mere savings.
4. For every candidate, record the current owner, replacement owner, exact change,
   estimated removable content, risk, preserved trigger/invariant/exception,
   one matching prompt, one neighboring prompt, one tie-breaker, and checks.
5. Report before editing. Include the baseline, ranked findings, conservative
   savings ranges, keep-separate decisions, skipped files, and a reversible apply
   order. State whether measurements are proxies or tokenizer-verified.
6. Apply only the named findings or bounded group the user explicitly approves.
   Re-run the inventory, inspect the complete diff, and validate routing and
   links after each group through `skill-authoring`.

## Approval boundary

No mode or a request to inspect means report-only. Words such as “optimize” or
“apply” do not authorize an unrelated sweep. An explicit implementation request
may authorize only the files and bounded change named by the user; otherwise stop
after the report and ask which findings to apply.

## Anti-patterns

- deleting repeated text solely because it repeats;
- replacing a portable rule with an unresolvable link;
- treating a frequency report as semantic equivalence;
- moving a high-risk rule behind an optional reference;
- applying a broad mechanical rewrite, commit, publication, or external action
  without explicit authorization.
