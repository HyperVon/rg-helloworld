---
name: docs-sync
description: >-
  Keep documentation synchronized after a change set — implementation-status
  log, README, architecture/runbook docs, ADRs, and versions pins. Use when
  shipping features, refactors, or dependency bumps that affect behavior or
  layout. For a full audit of all docs against source code, use
  documentation-review instead.
---

# Docs Sync

Incremental sync after a change set. For a whole-repo docs audit (missing,
wrong, stale), use [documentation-review](../documentation-review/SKILL.md).

## What to update when

| Change | Update |
| :--- | :--- |
| Any milestone work | `docs/implementation-status.md` (scope, tasks, acceptance, verification log) — always, before declaring done |
| Features, stack versions, commands, layout | `README.md` |
| Architecture, protocols, milestone order | `docs/architecture.md` + `docs/adr/` when the change is architectural |
| Artifact lineage / hashes | `docs/artifact-lineage.md` |
| Operation / troubleshooting commands | `docs/runbook.md`, `docs/troubleshooting.md` |
| Dependency or image version bumps | `versions.env`, per-language lockfiles, Helm chart pins — never `latest` tags |
| Agent workflows / quality paths | `AGENTS.md` task-to-skill table and relevant skills |
| Behavior in screenshots | `docs/screenshots/` (regenerate deterministically when artifacts change) |

## Ordering rule

Update `docs/implementation-status.md` **before** implementing (scope/tasks/
acceptance) and again after (verification log). Never leave the status doc
behind a completed milestone — work must be resumable after context
compression.

## Markdown hygiene

```bash
npx markdownlint-cli AGENTS.md README.md CONTRIBUTING.md SECURITY.md docs/**/*.md .agents/skills/**/*.md .kilo/**/*.md
```

(Adjust paths to the repository's lint configuration; `Makefile` may own a
markdownlint target.)

## Mermaid diagrams (architecture / runbook / README)

When adding or editing a ```mermaid fence, **parse it under Mermaid 8.x**
before finishing — IDE preview panes often lag GitHub's Mermaid and fail on
unquoted non-ASCII labels (`≥`) and the sequenceDiagram `actor` keyword.

```bash
python3 -m venv /tmp/rghello-mermaid
/tmp/rghello-mermaid/bin/pip install -q playwright
/tmp/rghello-mermaid/bin/python .kilo/scripts/validate_mermaid.py
# Or only the files you touched:
#   .../validate_mermaid.py docs/architecture.md docs/runbook.md
```

Syntax rules and the full audit path live in
[documentation-review](../documentation-review/SKILL.md) (Mermaid
compatibility).

## Checklist

- [ ] `docs/implementation-status.md` updated (scope + verification log)
- [ ] README / architecture / runbook / ADR touched when relevant
- [ ] versions.env and lockfiles synced with dependency changes
- [ ] `AGENTS.md` index updated when skills or norms changed
- [ ] Markdown lint clean on touched files
- [ ] Mermaid edits → `validate_mermaid.py` exit 0 (Mermaid 8.x / IDE baseline)
