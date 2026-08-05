---
name: ai-slop-detector
description: >-
  Audit and, when explicitly requested, clean up artifact-level AI slop across
  all repository assets: source code, tests, documentation, agent skills,
  agent rules, configuration templates, build scripts, and diffs. Finds
  evidence-backed quality defects such as needless complexity, excessive
  defensiveness, architecture drift, invented integrations, hallucinated
  API/cli claims, misleading docs, dead skill instructions, duplicate tests,
  and tests that do not protect required behavior. Never attributes authorship
  or intent to a contributor. Use for "AI slop", "AI-ish code", de-slopping,
  plausible-but-invented artifacts, mirror tests, or an artifact-level
  code-quality audit.
---

# Evidence-Based AI Slop Audit & Cleanup

**AI slop is not code or documentation written with AI.** It is an artifact
that appears plausible but imposes avoidable review, maintenance, correctness,
or safety cost because it lacks the judgment required by this repository's
contracts.

This skill evaluates **artifacts and their effects**, never a contributor's
tool use, competence, or intent. There is no reliable way to prove that an
asset was AI-generated. Emoji, unusual Unicode artifacts, verbosity, formulaic
prose, PR size, author history, or a contributor's answer to a question are,
at most, prompts to read more closely. They are not evidence of slop,
authorship, severity, or bad faith.

Default to an **audit and report**. Modify files only when the user explicitly
asks to clean up, eliminate, or fix findings.

## Scope and boundaries

This skill covers **all repository artifacts**, including:

1. **Source code**: all services (`services/*`), the CLI (`cmd/rghello`),
   and shared libraries (`libraries/`).
2. **Tests**: per-service unit tests, integration tests, golden artifacts,
   and the anti-cheating suite (`tests/anti-cheating/`).
3. **Documentation**: `docs/*` (architecture, implementation-status,
   runbook, artifact-lineage, ADRs), `README.md`, `CONTRIBUTING.md`,
   `SECURITY.md`.
4. **Agent skills**: skill instructions and resources (`.agents/skills/*`,
   `.kilo/skills/*`).
5. **Agent rules & guidance**: `AGENTS.md`, `.kilo/operating.md`, commands,
   and agents.
6. **Build & configuration**: `Makefile`, `versions.env`, per-language build
   files, `infra/` manifests, `contracts/` definitions.

| Skill | Use it for |
| :--- | :--- |
| **ai-slop-detector** (this) | Evidence-backed audit of needless complexity, invented behavior, misleading tests/docs/skills/rules, and architecture drift across all repo artifacts |
| [documentation-review](../documentation-review/SKILL.md) | Full factual documentation audit against source code |
| [rules-and-skills-audit](../rules-and-skills-audit/SKILL.md) | Structural consolidation (redundancy, index ordering, trigger conflicts) of rules and skills |
| [skill-reviewer](../skill-reviewer/SKILL.md) | Content improvements and domain depth for the agent playbook |
| [adversarial-pr-review](../adversarial-pr-review/SKILL.md) | Mandatory adaptive bounded multi-agent loop for a PR being opened or updated |
| [continuous-quality](../continuous-quality/SKILL.md) | QA-loop hardening of tests and edge cases |
| [autonomous-code-optimizer](../autonomous-code-optimizer/SKILL.md) | Unattended multi-pass refactor-to-zero; prefer for broad cleanup requests without a bounded audit |

This skill does not replace an applicable owner skill, mandatory PR workflow,
or quality gate. Load domain skills for touched code, especially
`rghello-milestone`.

## Evidence standard

Call something slop only when an observable artifact-level deficit is present.
Use the strongest evidence available:

1. **Reproduction or failing check**: compiler/type error, failing test,
   markdownlint error, unparseable YAML frontmatter, unsafe runtime behavior,
   security exposure, or broken user/agent flow.
2. **Explicit contract conflict**: an invariant in source, public API,
   contract schema, or protocol; or in tests, `AGENTS.md`, skills, and
   documentation after verifying they match source (source is the truth, not
   older docs).
3. **Local inconsistency with a cost**: duplicate mechanism, bypassed
   boundary, conflicting agent rule, dead skill instruction, or needless
   abstraction that demonstrably complicates maintenance or changes behavior.
4. **Review prompt only**: unusual style, size, formulaic or boilerplate
   prose, or a pattern with insufficient context. Investigate; do not report
   it as a defect.

Every finding needs all of the following:

- A source, contract, diff, test, skill, doc, or reproduction anchor.
- The actual or credible failure/maintenance outcome.
- The smallest safe correction, or a reason to defer.
- A severity based on impact, never on suspected AI involvement.

### Severity rubric

| Severity | Evidence-backed outcome |
| :--- | :--- |
| **P0** | Can leak the requested plaintext downstream, expose secrets/security, perform destructive action, invent an external API/config/dependency/tool that causes bad operation, state misleading security/integrity instructions in docs or skills, or conceal broken required behavior with test/doc changes |
| **P1** | Breaks the build, a code contract, an architectural boundary, a maturity-rank or artifact-provenance invariant, Kafka idempotency, skill YAML frontmatter, or required user/API/agent behavior; or creates directly conflicting agent rules that cause execution failure |
| **P2** | Demonstrably duplicates logic/instructions, demonstrably adds unneeded complexity, demonstrably weakens meaningful tests, leaves inaccurate/misleading documentation, or leaves stale/broken skill instructions or file links |
| **P3** | Reviewability or style issue with no demonstrated correctness/maintenance impact; normally suggest rather than change |

## Audit workflow

Copy this list and track it for non-trivial audits:

```text
- [ ] Step 0: Establish scope, contracts, and mode
- [ ] Step 1: Gather diff and high-risk evidence
- [ ] Step 2: Run validity checks
- [ ] Step 3: Inspect implementation, architecture, skills, rules, and docs fit
- [ ] Step 4: Inspect test independence and coverage intent
- [ ] Step 5: Inspect documentation, skills, agent rules, and integration claims
- [ ] Step 6: Classify and report evidence-backed findings
- [ ] Step 7: Apply minimal cleanup (only when requested)
- [ ] Step 8: Verify corrections and quality gates
```

### Step 0: Establish scope, contracts, and mode

1. Determine whether this is a file, diff, PR, subsystem, or full-repository
   audit. Check for changed code, tests, docs, skills (`.agents/skills/*`),
   rules (`AGENTS.md`, `.kilo/operating.md`), configuration, contracts, and
   build files.
2. Read `AGENTS.md`, then the owner skills and neighboring code/docs that
   establish the intended pattern.
3. State the mode: **audit** by default; **cleanup** only with explicit user
   direction. An audit does not silently refactor code or docs.
4. Identify high-risk paths first: plaintext/integrity boundaries, Kafka
   consumers, artifact provenance, credentials, persistence, concurrency,
   public routes, configuration, security docs, and skills/rules affecting
   execution safety.

For a large or broad diff, increase review depth or request a walkthrough of
the architecture, skills, and verification strategy. Diff size is a
review-budget signal, not evidence of slop.

### Optional parallel evidence pass

For a full-repository or broad PR audit, use the `ai-slop-detector` preset of
`.kilo/model-router/route-subagents` after Step 0 when explicit cross-provider
routing is wanted (see `.kilo/model-router/instructions.md`). It supplies
disjoint production/build, tests, docs/skills/rules, and contracts/generated
tracks. Workers return findings only; the parent owns severity triage,
cleanup decisions, edits, and serial quality gates. Do not fan out a small or
tightly coupled audit, and never use an unverified role-only worker.

### Step 1: Gather diff and high-risk evidence

For a PR or branch, inspect the diff before searching broadly:

- Production, test, build/dependency, configuration, contract, skill, rule,
  and document changes together.
- Added imports, dependencies, generated code, feature flags, settings,
  skill files, or agent rules.
- Assertions weakened or removed, tolerances widened, mocks broadened,
  error/edge cases deleted, or skill/doc safety instructions relaxed.
- Related source contracts and previous behavior when a test, doc, or skill
  change is unclear.

Use `git diff` and history to establish the expected behavior of a changed
asset. Do not infer motive from author tools.

### Step 2: Run validity checks

Run the smallest relevant checks early. Compilation, static analysis, linter
tools, and schema parsers catch invented imports, methods, APIs,
configuration, invalid skills, and broken markdown links better than prose
inspection does.

- Compile or test the affected service when feasible
  (`make build-<lang>`, `make unit-<lang>`).
- Run the repository's markdown lint on changed or audited markdown files.
- Verify skill YAML frontmatter (`name`, `description`) is valid and
  parseable.
- Run targeted tests for changed behavior.
- Inspect dependency declarations before accepting a new library/API claim.
- Check contract schemas, `versions.env` pins, and documentation claims
  against source code.
- Use the owning quality/documentation skills for full gates when the scope
  requires them.

Failure to run a costly check is not proof of a defect. Record the gap and
avoid overstating confidence.

### Step 3: Inspect implementation, architecture, skills, rules, and docs fit

Judge code against the standard of a strong staff engineer: defensive exactly
at trust boundaries (external protocols, Kafka/Redis, config, artifact
provenance), lean and confident inside them. Judge skills, rules, and
documentation against the standard of precision and alignment: clear,
accurate, non-conflicting, and verifiable against source code.

#### Meaningful artifact-level signals across repository assets

Investigate these only when there is an observable cost or contract conflict:

| Artifact Type | Signal | Establish the finding by showing |
| :--- | :--- | :--- |
| **Source Code** | Delegate-only wrapper or duplicate helper | No policy, transformation, error boundary, or reuse value; a direct existing call is clearer |
| **Source Code** | Generic/factory/DSL abstraction | It hides a simple stable case, adds change points, or duplicates an existing local pattern |
| **Source Code** | Invented integration or API | The dependency, route, method, config key, schema field, Kafka topic, or external API does not exist or is incompatible |
| **Source Code** | Excessive defensiveness / dead guards | The guarded state is contractually impossible; a fallback silently masks a hard failure; or duplicate validation adds no context |
| **Agent Skills** | Hallucinated tools, flags, or CLI commands | The skill instructs agents to use tools, parameters, flags, or shell commands that do not exist or fail |
| **Agent Skills** | Contradictions with code or rules | The skill instructs agents to violate source invariants or `AGENTS.md` rules (e.g. embedding expected characters downstream) |
| **Agent Skills** | Invalid frontmatter or dead links | YAML frontmatter is unparseable or missing required fields (`name`, `description`); or file/skill links are broken |
| **Agent Rules** | Rules drift / conflicting instructions | `.kilo/operating.md` or skills conflict with `AGENTS.md` or active source contracts |
| **Documentation** | Hallucinated parameters or routes | Docs list CLI flags, config keys, API endpoints, Kafka topics, or environment variables not present in source |
| **Documentation** | Inaccurate domain or safety claims | Docs state incorrect integrity rules, maturity ranks, hash-provenance behavior, or misleading security assumptions |
| **Documentation** | Pure AI fluff prose | Paragraphs of formulaic filler ("In this comprehensive guide...") that obscure operational facts |
| **Build & Config** | Pinned-version drift or invented targets | `versions.env` or lockfiles disagree with build files; Makefile targets documented but absent |

#### Context-dependent constructs

None of these is slop by itself. Inspect the surrounding contract before
reporting it:

| Construct | Valid examples | Report only when |
| :--- | :--- | :--- |
| `@Suppress` / `noqa` / lint ignores | File-local, narrowly scoped, with an evidence-based reason | It conceals a demonstrated type/warning issue without explanation or safer design |
| `catch (Exception)` | Application error boundary with logging/mapping/recovery | It swallows a needed failure or fails to rethrow cancellation |
| Blocking calls | Application startup/shutdown or a controlled blocking bridge | It blocks a request, worker, or latency-sensitive path |
| Single-use skill helper / script | Complex multi-step automation fixture isolated in `scripts/` | It duplicates an existing make target or contains hallucinated CLI calls |
| Detailed doc rationale | Explaining non-obvious safety invariants, integrity rules, or protocol semantics | It restates self-explanatory code line-by-line without domain rationale |

#### Repository-specific anchors

Check the actual owner skill/source instead of inventing a fourth pattern:

| Area | Contract to verify |
| :--- | :--- |
| Integrity rules | `docs/architecture.md` section 7: no plaintext/expected-character fields downstream of the glyph catalog; the CLI prints only `assembledText` |
| Artifact maturity | Ranks only increase along the primary path; every output artifact records input IDs and SHA-256 hashes |
| Contracts | `contracts/` is the single source of truth; generated code is never hand-edited; `make contracts` output matches |
| Kafka/Redis | Consumers idempotent (deterministic operation IDs); large payloads stay in MinIO, not Kafka/logs/Redis |
| Dependencies | Pinned versions in `versions.env` and lockfiles; no floating `latest` tags |
| Coverage | >= 90% per language where tooling allows; anti-cheating suite keeps passing |
| Agent Skills | Under `.agents/skills/*/SKILL.md`; valid YAML frontmatter; accurate trigger phrases; verified file/tool links |
| Agent Rules | Primary rules in `AGENTS.md`; `.kilo/operating.md` aligned; no absolute user paths or unvalidated settings |
| Documentation | `docs/*`, `README.md` must accurately reflect source behavior, CLI args, and protocol schema |
| Build & Config | `Makefile` targets exist as documented; `versions.env` matches per-language build files |

### Step 4: Inspect test independence and coverage intent

Tests are slop only when they fail to protect a stated behavior, actively
hide a required behavior, or add needless maintenance with no distinct defect
class. Do not use test count, LOC ratio, parameter count, or mocking alone as
proof.

#### Test independence checklist

- Derive the expected result from a contract, invariant, external protocol,
  or independently calculated oracle, not by duplicating the implementation's
  branch/formula.
- Ask whether a plausible wrong variant would fail: reversed comparison,
  wrong rounding, missing boundary, omitted error mapping, or incorrect
  collaborator order.
- Assert mock interactions when the interaction itself is the contract, such
  as protocol sequence, idempotency key, ordering, retry, or boundary
  delegation.
- Exercise null only for nullable/untrusted input; exercise concurrency only
  for shared/concurrent behavior.

#### Test necessity

Each test should be the cheapest way to kill a distinct defect class:

- Name the defect class the test uniquely covers. Cosmetic input variation
  with the same structure and no new failure mode is duplication, not
  coverage.
- Distinguish impossible from unlikely. Inputs the type system or caller
  contract make impossible do not need unit tests.
- Reject coverage padding: assertions that only prove "does not throw", "is
  not null", or restate a stubbed mock's return value with no production
  logic in between.

### Step 5: Inspect documentation, skills, agent rules, and integration claims

Documentation, skill, and rule slop is factual, operational, or execution
harm, not simply a terse style:

1. **Source Code Agreement**:
   - Commands, flags, imports, class/method names, routes, topics, config
     keys, and examples in docs, skills, and rules must agree with current
     source/build files.
2. **Setup and Safety Alignment**:
   - Instructions in README, skills, and rules must match real execution
     modes (acceptance vs dev), required infrastructure, local-trust
     assumptions, and defaults.
3. **Skill & Rule Integrity**:
   - Skills must have parseable YAML frontmatter (`name`, `description`).
   - Tool calls, flags, script paths, and Markdown links in skills must exist
     and work.
   - Rules in `.kilo/operating.md` must remain in sync with `AGENTS.md`.
4. **Fluff Removal & Rationale Retention**:
   - Remove generic AI filler prose ("In this section, we will discuss...")
     that adds no domain value.
   - Preserve non-obvious domain rationale, integrity-rule explanations, and
     protocol invariants.
5. **Handoff to Specialized Skills**:
   - Send broad documentation factual audits to `documentation-review`.
   - Send structural rules/skills consolidation to `rules-and-skills-audit`.
   - Send skill content enrichment to `skill-reviewer`.

### Step 6: Classify and report

Use neutral, concrete language: "the skill instructions reference a
non-existent `--force` flag on `make build`," not "the author generated a
fake skill." Keep unproven concerns in a questions/deferred section.

```markdown
# Artifact Quality Audit — {scope}

## Verdict
{N} findings: {P0} P0, {P1} P1, {P2} P2, {P3} P3.

## Findings
### [P1] {specific outcome} — `path:Lx-Ly`
- **Category:** code / test / docs / skill / rule / config
- **Evidence:** {reproduction, source contract, diff, or local comparison}
- **Impact:** {what can break, misinform agents, or become harder to maintain}
- **Smallest safe correction:** {concrete patch or owner-skill direction}
- **Verification:** {targeted test, markdownlint, or check}

## Review prompts / deferred
- {uncertain item, missing evidence, and the question needed to resolve it}

## Checks run
- {command or manual verification}: pass / fail / not run and why
```

### Step 7: Apply minimal cleanup only when requested

Keep corrections narrow and behavior-preserving unless the finding is a
proven bug or broken claim.

| Validated issue | Minimal correction |
| :--- | :--- |
| Redundant wrapper/abstraction | Inline/remove it or reuse the established helper, then prove callers retain behavior |
| Architecture/pattern drift | Move/delegate through the owning boundary and add a focused regression test |
| Invented or incorrect API / config claim | Replace with the verified API/dependency/config in code, docs, or skills; remove unsupported claims |
| Invalid skill frontmatter / broken link | Fix YAML frontmatter or correct/remove broken file/tool links |
| Conflicting agent rule instruction | Sync rule with `AGENTS.md` and active source code invariants |
| AI fluff prose in documentation | Prune filler words while retaining factual setup and safety rationale |
| Out-of-sync versions / build claims | Align `versions.env`, lockfiles, and Makefile targets with build files |
| Integrity-rule violation | Remove the plaintext/expected-character field at the boundary; add a guarding test |
| Mirror/weak test | Replace with a contract assertion that fails a plausible wrong variant |
| Duplicate / impossible-case test | Delete after proving its defect class is covered elsewhere or input is contractually impossible |

### Step 8: Verify corrections and quality gates

After cleanup:

- Run focused compilation/tests covering corrected code/contracts.
- Run the repository's markdown lint when markdown docs, skills, or rules
  are modified.
- Verify skill YAML frontmatter is valid.
- Run `make coverage` (and `make integration` / `make e2e` when the scope
  warrants) with `STRICT=1`; run gates serially, one at a time.
- For integrity, protocol, persistence, security, or cross-service changes,
  run domain/manual verification before declaring success.

## Anti-patterns

- Calling stylistic cues, contributor behavior, or PR size proof of AI use
  or slop.
- Labeling a familiar construct as bad without inspecting its boundary and
  contract.
- Inventing CLI flags, environment variables, or tool parameters in skills
  or documentation.
- Leaving broken Markdown links or unparseable YAML frontmatter in skill
  files.
- Deleting tests or doc rationale merely to reduce LOC or word count.
- Refactoring uncertain code or docs during an audit-only request.
- Skipping owner skills or quality gates after a validated cleanup.

## Trigger phrases

- "Audit this PR/codebase for AI slop"
- "Audit our skills and documentation for AI-ish claims or slop"
- "De-slop this file/skill/doc while preserving behavior and rationale"
- "Find hallucinated APIs, flags, config keys, or broken links in docs/skills"
- "Cut over-defensive padding, duplicate tests, and AI fluff prose"
- "Review this change for needless complexity, documentation drift, and rule
  conflicts"
