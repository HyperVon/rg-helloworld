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

For Mermaid edits, follow the canonical compatibility rules and validator in
[documentation-review](../documentation-review/SKILL.md#mermaid-compatibility).
Use that same validator before finishing; the checklist below records the
required verification.

## Checklist

- [ ] `docs/implementation-status.md` updated (scope + verification log)
- [ ] README / architecture / runbook / ADR touched when relevant
- [ ] versions.env and lockfiles synced with dependency changes
- [ ] `AGENTS.md` index updated when skills or norms changed
- [ ] Markdown lint clean on touched files
- [ ] Mermaid edits → `validate_mermaid.py` exit 0 (Mermaid 8.x / IDE baseline)
