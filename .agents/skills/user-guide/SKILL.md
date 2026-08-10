---
name: user-guide
description: >-
  Maintain the end-user walkthrough in `docs/user-guide.md` for the CLI, local
  pipeline, Web Shell, Artifact Inspector, observability surfaces, and runbook
  workflows. Use after user-facing behavior, routes, commands, or screenshots
  change; keep developer architecture in the canonical architecture docs.
---

# User Guide Maintenance

`docs/user-guide.md` is operator-facing documentation. It explains what a user
can run and see; it does not duplicate the full architecture, contract schemas,
artifact lineage, or implementation status.

## When to update

| Change | Update |
| :--- | :--- |
| CLI flag, output, or local run workflow | Command examples, expected output, and links to `docs/runbook.md` |
| Web Shell, Artifact Inspector, SSE, or observability route | Surface description, URL/port-forward, state, and troubleshooting notes |
| Artifact, maturity, lineage, or integrity behavior | Explain the operator-visible effect and link to `docs/artifact-lineage.md` / `docs/architecture.md` |
| Screenshot or visual layout change | Run [docs-screenshot-refresh](../docs-screenshot-refresh/SKILL.md), then update captions and image links |
| Removed or renamed behavior | Remove stale instructions and references; do not preserve an old command as if supported |

## Authoring rules

- Verify every command, route, service name, port, and flag against the current
  source, `Makefile`, README, and runbook. Do not copy a command from an older
  project or from a screenshot.
- Use plain language and an operator-first sequence: prerequisites, quick start,
  what the pipeline does, UIs, focused service runs, troubleshooting, and
  cleanup. Link to deep architecture rather than copying it.
- Keep acceptance and integrity claims precise. Never expose requested
  plaintext in downstream examples, credentials, tokens, personal paths, or
  raw runtime logs.
- Screenshot captions must describe the captured state honestly. Use relative
  paths under `docs/screenshots/`, keep the README visual set curated, and
  ensure every referenced image exists.

## Verification checklist

- [ ] Commands and URLs read back from current source/build/runbook
- [ ] CLI acceptance output and exit behavior remain accurate
- [ ] UI pages, states, and troubleshooting steps match fresh evidence
- [ ] Screenshot links, alt text, and captions are current
- [ ] Architecture/lineage/security links point to the owning documents
- [ ] Markdown lint and `git diff --check` pass
