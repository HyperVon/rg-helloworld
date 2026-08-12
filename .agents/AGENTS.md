# AGENTS.md

Guidance for AI coding agents working in this repository. Read this file before
making changes.

## Project

Rube Goldberg Hello World: a deliberately excessive, fully local distributed
system whose only purpose is to derive and print `Hello World` through
vector glyphs -> geometry -> SVG -> raster images -> phrase image -> OCR ->
adjudication -> assembly.

- Authoritative architecture: `docs/architecture.md` (read the relevant
  sections before any milestone work).
- Authoritative status: `docs/implementation-status.md` (update it with every
  milestone; work must be resumable after context compression).
- Acceptance: `rghw run` prints exactly `HELLO WORLD` and exits 0, with the
  phrase derived from OCR-derived artifacts — never printed from the request.

## Non-negotiable integrity rules

1. Only the CLI, orchestrator, and glyph catalog may see the requested
   plaintext before final validation.
2. No downstream event may contain `targetText`, `expectedCharacter`,
   `unicodeCodePoint`, `characterName`, or equivalent fields.
3. OCR and adjudication must never receive the expected output.
4. The Rust assembler assembles only accepted OCR-derived symbols.
5. The CLI prints only the orchestrator's terminal `assembledText`.
6. Every primary transformation must increase the artifact maturity rank
   (0 -> 10 -> 20 -> ... -> 100).
7. Source code (excluding tests and contract examples) must not contain the
   clear-text phrase "Hello World" or variants. Use obfuscation languages
   like Whitespace or Brainfuck where needed for transformations. The CLI
   executable is named `rghw` (not `rghw` or any variant of "Hello World").
8. Every output artifact records input artifact IDs and SHA-256 hashes.
9. Kafka consumers must be idempotent (deterministic operation IDs).
10. No paid service or external runtime API, ever.
11. The whole acceptance environment runs on one laptop.

## Milestone workflow

`docs/architecture.md` section 29. Never start the next milestone while the
current one's acceptance conditions fail.

For each milestone:

1. Read the relevant architecture sections.
2. Update `docs/implementation-status.md`: scope, tasks, acceptance
   conditions.
3. Implement the smallest complete milestone.
4. Add tests before proceeding. Coverage must be >= 90% per language where
   tooling allows (enforced by `make coverage`, CI-gated).
5. Run targeted checks during iteration; run the milestone's full checks
   before completion.
6. Update documentation.
7. Commit the milestone as one coherent change **only when explicitly
   authorized** to commit.

## Required commands

From the repository root:

```bash
make prerequisites   # toolchain check + language deps (venv, npm ci, bundle)
make format          # format all languages
make lint            # lint all languages (STRICT=1 fails on missing tools)
make unit            # unit tests for all skeleton services
make coverage        # unit tests + 90% coverage gates
make build           # compile everything
make integration     # cross-language artifact integration tests
make e2e             # full milestone acceptance (gates + integration)
```

Missing toolchains are skipped with a warning unless `STRICT=1` is set.
CI always runs strict. Run `make format` before `make lint`; the two must both
pass before a milestone is complete.

## Documentation freshness

`docs/implementation-status.md` is the authoritative status and must be
updated with every milestone (scope, tasks, acceptance, verification log).
Any change that alters behavior, commands, or structure must update the
relevant documentation (README, service READMEs, runbook, ADRs) **in the
same change** — never leave docs behind.

## Language ownership

Do not combine service implementations into one language, and do not bypass a
protocol the architecture requires:

| Language | Owns |
| --- | --- |
| Go | `cmd/rghw` (CLI), `services/vector-normalizer-go` |
| Kotlin | `services/run-orchestrator-kotlin` (orchestrator) |
| Java | `services/glyph-catalog-java` (SOAP glyph catalog) |
| C++ | `services/geometry-engine-cpp` |
| C#/.NET | `services/rasterizer-dotnet` (gRPC rasterizer) |
| Python | `services/image-pipeline-python` |
| TypeScript/Node.js | `services/ocr-worker-node`, `services/event-gateway-node` |
| Ruby | `services/adjudicator-ruby` |
| Rust | `services/phrase-assembler-rust` |

Kafka and Redis are both required and are not interchangeable. Kubernetes
(k3d/k3s) is the acceptance environment; Docker Compose may only be an
optional focused-development aid.

## Engineering rules

- Work contract-first: `contracts/` is the single source of truth for all
  inter-service boundaries (`make contracts` regenerates clients and models;
  generated code is never hand-edited).
- Pin every dependency and container version. Never use floating `latest`
- All dependencies must use free and open-source licenses (MIT, Apache-2.0, BSD, ISC, MPL-2.0, LGPL, CC0, Unlicense, or Public Domain). No commercial or attribution-only licenses are permitted. See `docs/adr/0010-licensing.md` for the full policy.
  tags. Update `versions.env` and the per-language lockfiles.
- Prefer deterministic outputs (fixed seeds, quantized floats, sorted output).
- Use structured JSON logs in services (later milestones); never log the
  requested plaintext, credentials, image bytes, or huge payloads.
- Propagate OpenTelemetry trace context through HTTP, SOAP, gRPC, and Kafka.
- Keep large payloads in MinIO, not in Kafka, logs, Redis, or command output.
- Treat every deprecation warning as actionable: resolve it before completion;
  if resolution is not possible, document the exact warning, the blocking
  constraint, the mitigation, and the follow-up owner or trigger. Never leave
  deprecations silently unresolved.
- No unapproved architecture changes; record changes as ADRs under
  `docs/adr/`.

## Skills and agents

Always-on norms live canonically in `.agents/OPERATING.md`. Harness-specific
entrypoints and projections (including `.kilo/operating.md` via `kilo.json`)
should remain thin and aligned with that file. For a task that matches a skill,
read and follow that skill before inventing a process. Portable skills live in
`.agents/skills/` (Kilo also exposes `.kilo/skills/` via `kilo.json` `skills.paths`).
Kilo commands and agents live in `.kilo/command/` and `.kilo/agent/`. The cross-project integration decisions are
recorded in [the guidance review](docs/agent-guidance-integration-review.md).

| User intent | Skill / command |
| --- | --- |
| Implement / resume a milestone | `rghw-milestone` (`.kilo/skills/`) |
| Run gates / evidence before changes | `/quality-gate` |
| Review working-tree changes before commit | `/review-diff` |
| Boot the acceptance stack and verify | `/acceptance-smoke` |
| Review a diff or subsystem | `code-review` |
| Commit / push | `commit-and-push` |
| Open PR | `open-pr` (+ mandatory `adversarial-pr-review`) |
| Adversarial / multi-agent PR review | `adversarial-pr-review` |
| Artifact-quality / "de-slop" audit | `ai-slop-detector` |
| Docs audit vs source truth | `documentation-review` |
| Incremental docs sync after a change | `docs-sync` |
| Review skills for content depth | `skill-reviewer` |
| Audit rules/skills structure, overlap, drift | `rules-and-skills-audit` |
| Audit or stage external agent guidance safely | `agent-foundation-audit` |
| Create or modify a skill | `skill-authoring` |
| Fan-out parallel work | `parallel-multi-agent` |
| QA loop / test hardening | `continuous-quality` |
| Broad bounded improvement cycle | `continuous-improvement` |
| Comprehensive read-only quality sweep | `comprehensive-quality-overhaul` |
| Unattended multi-pass cleanup | `autonomous-code-optimizer` |
| TODO burn-down | `todo-resolution` |
| Comment hygiene / explain complex code | `complex-code-comments` |
| Dependency upgrades | `dependency-upgrade` |
| Architecture review / redesign brainstorm | `architecture-review` |
| Code-size reduction / large-file splits | `reduce-code-size` |
| Manual browser interaction QA | `ui-manual-qa` |
| Fast post-deploy UI smoke | `post-deploy-ui-smoke` |
| Refresh committed UI screenshots | `docs-screenshot-refresh` |
| Maintain the end-user guide | `user-guide` |

## Context and output discipline

- Use quiet test modes; capture complete logs in files under
  `.local/diagnostics/`.
- Show only relevant failure excerpts; never dump entire dependency trees or
  full Kubernetes manifests.
- Prefer the `kops` MCP tools (`k8s_get`, `k8s_describe`, `k8s_logs`,
  `k8s_events`, `k8s_triage`, `k8s_inventory`) over raw `kubectl` for
  read-only cluster inspection; use `kubectl logs --tail`, bounded
  `grep`/`head` for anything else.
- Summarize command results instead of repeating thousands of lines.

## Kilo session hygiene (prevent output-limit failures)

This repo's sessions are long and context-heavy, which can trigger "model hit
its output limit while reasoning and produced no actionable output":

- Work in small increments; verify each piece before the next, doing the same
  for long-lived sessions by compacting them (`/compact`) before large code
  generation steps; context growth increases reasoning, which consumes
  output budget.
- If the output-limit error still occurs, re-run the message unchanged
  (retries usually succeed), switch models (`/models`) to one with a higher
  output cap, or toggle reasoning (`/thinking`) before retrying.
- On resume after context compression, rely on `docs/implementation-status.md`
  and the rghw-milestone skill instead of pasting large transcripts.
- Never dump full file contents, dependency trees, or command output into a
  prompt; keep queries pointed at the files that changed.

## Code style

- Write readable, idiomatic code for each language; follow the per-language
  linters and formatters configured in this repo (gofmt/go vet, Spotless,
  ktlint, clang-format, dotnet format, ruff, prettier/tsc, rubocop,
  rustfmt/clippy).
- Do not add explanatory comments; let the code speak. Keep comments only
  where language conventions require them (e.g., exported Go identifiers).

## Testing

- Every service has unit tests; keep coverage at 90% or higher where the
  tooling supports measurement.
- Golden artifacts, contract tests, integration tests, and e2e tests arrive
  with their milestones; never delete a test that guards an integrity rule.
- The anti-cheating suite (`tests/anti-cheating/`) must keep passing once it
  exists (Milestone 1+).

<!-- agent-guidance-kit:routes:start -->
## Agent Guidance Kit skills

These receipt-managed skills were adopted from Agent Guidance Kit.

| Task | Skill |
| :--- | :--- |
| Adopt, add, audit, refresh, or update Agent Guidance Kit content | [agent-guidance-maintenance](skills/agent-guidance-maintenance/SKILL.md) |
| Search and triage catalog expansion candidates from public sources | [catalog-discovery](skills/catalog-discovery/SKILL.md) |
| Branch, commit, PR, and release hygiene for Git and GitHub | [git-github-workflow](skills/git-github-workflow/SKILL.md) |
| Adapt canonical guidance to the active agent harness | [harness-adaptation](skills/harness-adaptation/SKILL.md) |
| Review security boundaries, authority, secrets, and sensitive data flows | [security-review](skills/security-review/SKILL.md) |
| Reduce guidance context cost without weakening behavior | [skill-optimizer](skills/skill-optimizer/SKILL.md) |
| Diagnose an observed failure and find its root cause before fixing it | [systematic-debugging](skills/systematic-debugging/SKILL.md) |
| Propose local skill improvements upstream via fork and PR | [upstream-contribution](skills/upstream-contribution/SKILL.md) |
<!-- agent-guidance-kit:routes:end -->
