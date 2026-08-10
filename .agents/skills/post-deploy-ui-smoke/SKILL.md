---
name: post-deploy-ui-smoke
description: >-
  Run a fast read-only smoke check after deploying or rebuilding a browser UI:
  hard-refresh the affected routes, verify health and critical status, and
  capture failures. Use for post-deploy regressions; escalate to ui-manual-qa
  for broad interaction testing.
---

# Post-deploy UI Smoke

Use this short check when a deployed local UI looks stale or broken. It
complements [ui-manual-qa](../ui-manual-qa/SKILL.md) and is not a substitute for
full QA after a broad feature change.

## Workflow

1. Read `docs/runbook.md` for the current base URL, port-forward, health route,
   and changed surface. Do not guess a route or credential.
2. Hard-refresh the affected page and confirm the current CSS/JavaScript asset
   is served. A cached page is not evidence after a rebuild.
3. Check health, navigation, page load, critical status/terminal state, and the
   one or two interactions directly affected by the deployment. Use a laptop
   viewport and a phone viewport; add responsive widths when the change is
   responsive.
4. Capture a screenshot or browser snapshot for each failure and record the
   exact expected versus actual result under `.local/diagnostics/`.
5. Report pass/fail/blocked. Escalate to full `ui-manual-qa` when more than a
   single localized check fails, when stateful interactions changed, or when
   visual evidence cannot establish the result.

## Safety

- Read-only against an already-running deployment unless the user explicitly
  authorizes a local rebuild or redeploy.
- Never change credentials, integrity settings, or external/live services.
- Do not stop shared processes or tear down infrastructure you did not start.

```markdown
# Post-deploy UI smoke — YYYY-MM-DD
- URL/surface: …
- Fresh asset check: pass | fail
- Health/navigation: pass | fail
- Changed interaction: pass | fail | skipped
- Viewports: …
- Evidence: …
- Escalation: none | ui-manual-qa
```
