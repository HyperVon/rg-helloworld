---
name: code-review
description: >-
  Structured evidence-based review of a diff or subsystem across the
  repository's polyglot services, contract-first boundaries, integrity rules,
  concurrency, and test quality. Use when reviewing code or a change set; PR
  readiness still routes through open-pr and adversarial-pr-review.
---

# Code Review

Review code against repository contracts and observed source truth. This is a
recommendation-first review workflow, not an automatic refactor.

## Boundary

| Skill | Owns |
| :--- | :--- |
| **code-review** (this) | Focused diff or subsystem review and findings |
| [adversarial-pr-review](../adversarial-pr-review/SKILL.md) | Adaptive bounded review required for PR creation or updates |
| [ai-slop-detector](../ai-slop-detector/SKILL.md) | Evidence-based artifact-quality and test-independence audit |
| [architecture-review](../architecture-review/SKILL.md) | Recommend-only redesign and boundary alternatives |
| [open-pr](../open-pr/SKILL.md) | PR gates, body, and creation |

Use this skill alone for a focused engineering review. Do not duplicate a full
AI-slop audit or claim PR merge readiness from this checklist alone.

## Step 0 — Establish review truth

1. Inspect `git status`, the complete diff, and the merge base when a change
   set is named. Review the whole changed surface, not only the first file.
2. Read the relevant `docs/architecture.md` sections,
   `docs/implementation-status.md`, contract schemas, service README, and
   existing tests before judging a behavior.
3. Identify whether the change crosses a contract, generated-code boundary,
   service language boundary, milestone acceptance condition, or UI surface.
4. Run `git diff --check`; record unrun gates as verification gaps, not as
   implicit passes.

## Review dimensions

### Boundaries and design

- `contracts/` is the source of truth; generated clients/models are regenerated
  and never hand-edited.
- Each service keeps its assigned language and required protocol. Do not accept
  a shortcut that moves behavior across a boundary just to simplify a test.
- Keep pure transformation logic separate from network, storage, broker, and
  process concerns. Flag wrappers or abstractions without a current seam.
- Validate each contract at its owning boundary. Avoid duplicated validation,
  guards for impossible states, and silent fallbacks that hide failure.

### Integrity and artifact lineage

- Only the CLI, orchestrator, and glyph catalog may see requested plaintext
  before final validation; downstream events must not carry expected-character
  or equivalent fields.
- OCR and adjudication must remain unaware of the expected output, and the
  Rust assembler may use only accepted OCR-derived symbols.
- Maturity ranks increase monotonically. Outputs record input artifact IDs and
  SHA-256 hashes, and the CLI prints only the orchestrator terminal result.
- Kafka consumers use deterministic operation IDs and remain idempotent. Kafka,
  Redis, MinIO, and required HTTP/SOAP/gRPC/SSE boundaries are not
  interchangeable.

### Runtime, security, and operations

- Check retries, cancellation, timeouts, duplicate delivery, out-of-order
  events, backpressure, and restart behavior at the affected boundary.
- Keep large payloads in MinIO rather than events, Redis, logs, or command
  output. Preserve trace context across supported protocols.
- Reject credentials, tokens, personal absolute paths, machine-specific
  hostnames, plaintext output, and raw provider errors in source or committed
  artifacts. Dependency and image versions remain pinned; no `latest`.
- Treat deprecation warnings as actionable and record exact unresolved cases.

### Tests and evidence

- Each new test protects a distinct defect class and derives expectations from
  contracts or an independent oracle. Flag mirror tests, padding, and tests
  that only execute code without asserting behavior.
- Coverage stays at least 90% per language where the tooling supports it. Keep
  contract, integration, e2e, chaos, and anti-cheating tests when the changed
  behavior requires them.
- Run targeted checks while reviewing and the required `make` gates serially;
  add `make integration` or `make e2e` for cross-service changes.
- For user-visible UI changes, require fresh assets, changed interactions, and
  viewport evidence according to `.kilo/operating.md` §11.

### High-risk defect categories

- *Concurrency & atomicity:* unlocked mutexes/locks on early return or exception paths; check-then-act (TOCTOU) races; goroutine/thread/task leaks without lifecycle termination; unhandled promise/async task rejections.
- *State transitions & persistence:* partial multi-step persistence writes lacking transaction rollback; missing connection/handle release in `finally`/`defer` blocks; idempotency failures during retries.
- *Input & boundary validation:* missing bounds, size, or type checks on untrusted payloads; unescaped inputs reaching regex/SQL/shell parsers; sensitive data leaked into log lines.
- *Error propagation:* swallowed exceptions returning synthetic default values that masquerade as success; missing error wrapping that loses operational root cause.

## Findings format

Report concrete outcomes with evidence and a smallest safe correction:

```markdown
# Code Review Summary

## Strengths
- …

## Findings
### [P0|P1|P2|P3] Short outcome — `path:Lx-Ly`
- Category: boundary | integrity | runtime | security | tests | docs | UI
- Evidence: …
- Impact: …
- Suggested correction: …

## Verification gaps
- Gate or evidence not run: …

## Deferred / questions
- …
```

P0 means an acceptance, integrity, security, or data-loss blocker; P1 is a
material correctness or contract defect; P2 is a localized maintainability or
coverage issue; P3 is a low-risk improvement. Do not edit code while reviewing
unless the user explicitly asks to apply selected findings.

### Reviewer anti-patterns

- *Style nitpicking:* do not report formatting or subjective syntax preferences when linters pass and the code matches local conventions.
- *Speculative vulnerabilities:* do not report security flaws without a concrete untrusted data flow, unverified input, or reachable abuse path.
- *Scope creep & unsolicited redesign:* do not demand an architectural rewrite when reviewing a localized fix or narrow feature.
- *Phantom verification:* never claim tests passed or code is verified without running the exact test command and inspecting output.

## Completion checklist

- [ ] Complete changed surface and relevant source-of-truth documents read
- [ ] Contract, integrity, protocol, and language ownership checks performed
- [ ] Test independence and required gate coverage assessed
- [ ] UI evidence requested when the change is user-visible
- [ ] Findings include paths, evidence, impact, and severity
- [ ] Review coverage checked against the frozen scope; what was NOT inspected is stated
- [ ] No commit, push, PR, or remote issue was created by the review
