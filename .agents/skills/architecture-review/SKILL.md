---
name: architecture-review
description: >-
  Recommend-only third-party architecture review of the repository or a
  subsystem — discovers the design from code, stress-tests it against the
  integrity rules and milestone plan, and delivers a Keep / Evolve / Replace /
  Greenfield decision report with a decisions file. Use when the user asks for
  an architecture review, design brainstorm, ADR planning, or
  redesign-vs-refactor assessment.
---

# Architecture Review

A **recommend-only** review: the parent owns the report and any decisions.
Deliver the smallest useful decision report, not a rewrite proposal. This
repository's milestone order (`docs/architecture.md` section 29) and integrity
rules (section 7) are constraints, not review targets.

## How this differs from nearby skills

| Skill | Role |
| :--- | :--- |
| **architecture-review** (this) | Redesign / refactor-vs-keep decision for the product architecture |
| [documentation-review](../documentation-review/SKILL.md) | Make docs match code (factual sync) |
| [ai-slop-detector](../ai-slop-detector/SKILL.md) | Artifact-level quality audit |
| [rghw-milestone](../../../.kilo/skills/rghw-milestone/SKILL.md) | Implement the current milestone in order |

## Workflow

1. **Scope** — repo, subsystem, or milestone slice; state the review question.
2. **Discover from code** — docs are claims, not truth. Map services,
   `contracts/`, Kafka topics, artifact pipeline, and `infra/` from source and
   Makefile targets.
3. **As-is map** — one page: service graph, protocol boundaries (SOAP, gRPC,
   HTTP, Kafka, SSE), artifact maturity path (0 → 10 → … → 100), and the
   acceptance flow (`rghello run`).
4. **Stress-test dimensions** (use the ones that apply):
   - Integrity rules: any place plaintext/expected-character fields could
     leak below the glyph catalog?
   - Artifact provenance: input IDs + SHA-256 hashes recorded at every
     transformation; ranks monotonic?
   - Contract-first: `contracts/` single source; generated code untouched?
   - Kafka/Redis semantics: consumer idempotency, ordering, large-payload
     policy (MinIO)?
   - Milestone order: does the slice respect section 29 sequencing?
   - Local-trust/security: one-laptop assumption, no external runtime APIs,
     secrets handling.
   - Observability: trace propagation, structured logs, diagnostics.
   - Testing: 90% coverage gates, anti-cheating suite, golden artifacts.
   - Operability: runbook accuracy, k3d boot/teardown, determinism.
5. **Alternatives** — for each stress finding, generate Keep / Evolve /
   Replace / Greenfield options. Alternatives must be comparable, including
   **keep-current** with its costs.
6. **Filter** — apply three gates: impact (what breaks if we do nothing),
   evidence (is the premise proven?), cost (effort vs milestone budget).
7. **Deliver** — report with P0–P3 severities plus a **decisions file** (one
   markdown file under `docs/adr/` or a dated review file) listing each
   finding with options, recommendation, and handoff. Do not edit source.

## Severity

| Sev | Meaning |
| :--- | :--- |
| **P0** | Integrity-rule or safety flaw (plaintext leak risk, broken provenance) |
| **P1** | High-leverage architecture gap that blocks or complicates a milestone |
| **P2** | Valuable improvement; safe to defer |
| **P3** | Optional polish; no demonstrated impact |

## Anti-patterns

- Rubber-stamping the existing design ("looks fine") without evidence
- "Rewrite because popular" with no impact/evidence gate
- Microservices theater or new abstractions with no current seam
- Proposing changes that violate the milestone order or integrity rules
- No decision file — recommendations must survive context compression

## Output shape

```markdown
# Architecture review — {scope} — YYYY-MM-DD

## Verdict
…

## As-is summary
…

## Findings
### [P1] Title — path:line
- **Evidence**: …
- **Options**: Keep (cost) / Evolve (cost) / Replace (cost) / Greenfield (cost)
- **Recommendation**: …
- **Handoff**: decision recorded in docs/adr/…

## Decisions file
`docs/adr/YYYYMMDD-<slug>.md` with the above per finding.
```

Record decisions in the decisions file so follow-up sessions can act without
re-reading the review. Do not implement anything unless the user separately
approves the recommended option.
