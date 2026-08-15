---
name: frontend-quality-review
description: >-
  Review an implemented frontend, UI, or UX surface for evidence-backed
  product quality, interaction, accessibility, responsive, state, and
  performance defects. Use for explicit UI quality or accessibility reviews;
  do not use for ordinary backend code review, net-new implementation, or
  optional visual redesign without a demonstrated defect. Report by default;
  do not edit or automate a browser without separate authorization.
---

# Frontend Quality Review

## Contract

- **Input:** the UI scope, product/user/job intent, available design references,
  target viewport or platform assumptions, and authorized review level.
- **Output:** prioritized findings with precise evidence, user impact, smallest
  correction, acceptance criteria, verification status, and remaining gaps.
- **Owner:** implemented frontend interaction, accessibility, responsive, and
  visual-quality review.
- **Non-goals:** net-new UI implementation, generic beautification, authorship
  detection, a universal aesthetic blacklist, browser automation, or declaring
  a surface acceptable without fresh evidence.
- **Side effects:** read-only by default; edits, screenshots, browser actions,
  and external service access require separate explicit authority.

## Review workflow

1. **Establish intent and scope.** Identify the user/job, primary action,
   information hierarchy, navigation model, design-system or reference
   evidence, supported viewports, and what was not supplied. Do not invent a
   product brief from visual taste.
2. **Inspect the implementation and source of truth.** Read the changed UI,
   routes, components, styles/tokens, assets, tests, and relevant product or
   accessibility requirements. Separate implementation evidence from optional
   preference.
3. **Review behavior and states.** Check loading, empty, error, success,
   disabled, permission, validation, focus, keyboard, navigation, and recovery
   states. Trace the primary task through normal, boundary, and failure paths.

   **Core interaction & accessibility checklist:**
   - *Keyboard navigation:* Focus traps in modals/dialogs (missing `Escape` listener, missing focus restore on close); interactive elements reachable and operable via `Tab`/`Enter`/`Space`.
   - *Form controls:* Every input/select/textarea must have a programmatic label (`<label for="...">`, `aria-label`, or `aria-labelledby`); placeholder text is not an accessible label.
   - *Dynamic state & alerts:* Async status, error banners, and toast notifications must announce via `aria-live="polite"` or `role="alert"`.
   - *Semantic interactive elements:* Buttons and links must use `<button>` and `<a>` (or explicit `role="button"` with `tabIndex="0"` and keyboard handlers); do not use bare `<div onClick=...>` without keyboard equivalents.
   - *Async form protection:* Submit buttons must disable or indicate pending state during in-flight async requests to prevent duplicate submission or double charging.
   - *Form error recovery:* On validation failure, focus must be programmatically moved to the error summary or first invalid field, and invalid inputs must declare `aria-invalid="true"`.
4. **Review responsive and accessible behavior.** Check semantic controls,
   labels, focus visibility and order, keyboard reachability, contrast, zoom or
   text resizing, reduced motion, touch targets, responsive overflow, and
   content resilience. Treat automated checks as partial evidence, not a full
   accessibility verdict.
5. **Review visual and performance quality.** Check hierarchy, typography,
   spacing, density, imagery, motion, consistency, layout stability, and
   obvious waterfall or rendering cost against the stated product intent. Do
   not call a distinctive design defective merely because it is unfamiliar.
6. **Report and stop.** For every finding give severity, exact path or state,
   evidence, user impact, smallest correction, and verification probe. State
   missing references, untested states, and unresolved assumptions. Stop in
   report-only mode unless the user separately authorizes changes.

   **Severity rubric and report format:**
   - **P0:** Critical blocker preventing task completion (e.g. broken checkout submit, keyboard trap preventing navigation, fatal render crash).
   - **P1:** Material interaction or accessibility defect (e.g. double submission vulnerability, missing form label, error recovery state broken, contrast failure on key action).
   - **P2:** Responsive clipping, missing loading skeleton/state, visual misalignment against tokens, or minor focus indicator flaw.
   - **P3:** Minor visual consistency or micro-interaction polish.

## Routing boundaries

- Use `code-review` for a focused code diff whose main question is correctness,
  even when it contains UI code.
- Use `ai-slop-detector` for a broad artifact-quality audit or invented UI/code
  claims; hand off here when the request becomes a complete UI-quality review.
- Use `quality-hardening` for test and regression gaps, and `security-review`
  for security boundaries or sensitive data flows.

Do not infer intent, authorship, or quality from framework choice, visual style,
emoji, or generated-code signals alone. A clean review means no evidence-backed
defect was confirmed in the examined scope; it does not prove universal
usability or accessibility.
