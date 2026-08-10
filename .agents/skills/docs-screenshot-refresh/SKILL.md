---
name: docs-screenshot-refresh
description: >-
  Refresh and verify the repository's committed UI screenshots after web-shell,
  artifact-inspector, observability, or documentation changes. Use when images
  under `docs/screenshots/` or their README/runbook/user-guide presentation may
  be stale; use ui-manual-qa for functional click-through testing.
---

# Documentation Screenshot Refresh

Keep `docs/screenshots/` honest and visually useful. Screenshots are acceptance
evidence for the local web experience, not decoration generated from code
inspection.

## Boundary

- This skill captures and visually verifies documentation images.
- [ui-manual-qa](../ui-manual-qa/SKILL.md) verifies interactions and reports
  functional failures without redesigning.
- [docs-sync](../docs-sync/SKILL.md) decides which product/runbook docs change.
- Do not alter application code or redesign a UI as part of a refresh unless
  the user separately asks for that implementation.

## Preconditions and stack

1. Read the relevant sections of `docs/runbook.md` and identify the exact
   current routes, port-forwards, credentials handling, and screenshot targets.
2. Use the local stack only. Start or reuse the documented sequence as needed:
   `make cluster`, `make images`, `make infra`, `make deploy`, `make wait`, and
   the documented demo/run command. Do not invent endpoints or copy secrets
   into a capture directory.
3. Do not tear down a cluster or stop processes you did not start. Keep owned
   long-lived processes in the background and record bounded logs under
   `.local/diagnostics/`.

## Capture workflow

1. Establish a successful, representative local run before taking stateful
   captures. Use the current run/artefact identifiers from that run; do not
   preserve personal hostnames, credentials, tokens, or misleading stale IDs in
   documentation.
2. Rebuild or redeploy the affected UI and hard-refresh the browser. Confirm
   that current CSS/JavaScript and image assets are served; a cached page is not
   evidence.
3. Capture the affected pages from the documented UI set, normally Web Shell,
   Artifact Inspector, and any changed observability surface. Use the existing
   Playwright/browser capture mechanism if configured; otherwise use the
   available local browser capture tool and record the method.
4. Use the documentation baseline (currently a laptop-sized capture) plus
   phone/tablet/desktop/wide captures when responsive behavior or layout is
   affected. Use DPR 2 where the capture tool supports it.
5. Read every newly generated PNG at its actual presentation size. Check for
   loading/empty/error states, clipped content, stale labels, broken images,
   unreadable text, and a truthful caption. Code and filenames alone are not
   visual verification.
6. Update only the affected references in `README.md`, `docs/runbook.md`, and
   `docs/user-guide.md`. Keep the README curated; do not add every diagnostic
   frame to the public image set.

## Verification and cleanup

- Confirm every referenced image exists, has a useful alt text/caption, and
  renders from the document's relative path.
- Run `git diff --check` and Markdown lint on changed docs. Run the relevant
  web-shell/artifact-inspector checks and full gates required by the change.
- Keep throwaway captures, logs, and run metadata under `.local/diagnostics/`;
  do not commit them unless the repository explicitly defines them as fixtures.
- Stop only processes owned by this run and leave shared local infrastructure
  in the state the user expects.

## Completion checklist

- [ ] Representative local run and fresh assets confirmed
- [ ] Affected pages captured at the required viewport sizes
- [ ] Every new image visually inspected
- [ ] README/runbook/user-guide references match current routes and files
- [ ] No credentials, personal paths, or stale operational claims captured
- [ ] Markdown, targeted tests, and applicable gates recorded
