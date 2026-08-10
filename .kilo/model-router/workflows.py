"""Bounded track presets for project skills that support parallel discovery."""

from __future__ import annotations

from typing import Any


def _track(
    track_id: str,
    profile: str,
    agent: str,
    files: list[str],
    focus: str,
) -> dict[str, Any]:
    return {
        "id": track_id,
        "profile": profile,
        "agent": agent,
        "files": files,
        "read_only": True,
        "task": focus,
    }


WORKFLOW_TRACKS: dict[str, list[dict[str, Any]]] = {
    "documentation-adversarial-review": [
        _track(
            "finding-verification",
            "agentic",
            "docs-contract-auditor",
            ["README.md", "docs/", "CONTRIBUTING.md", "SECURITY.md", ".agents/skills/documentation-review/"],
            "Independently verify every parent-supplied documentation finding against current source, tests, and build truth.",
        ),
        _track(
            "completeness-sweep",
            "agentic",
            "explore",
            ["README.md", "docs/", ".agents/", ".kilo/", "services/", "contracts/", "Makefile", ".github/workflows/"],
            "Search for documentation issues missed by the parent review and report only distinct evidence-backed findings.",
        ),
        _track(
            "severity-evidence",
            "critical",
            "docs-contract-auditor",
            ["README.md", "docs/", "SECURITY.md", "CONTRIBUTING.md", ".agents/"],
            "Challenge finding severity, categorization, evidence strength, and proposed fixes; reject preference-only claims.",
        ),
    ],
    "documentation-review": [
        _track(
            "product-docs",
            "routine",
            "docs-contract-auditor",
            ["README.md", "CONTRIBUTING.md", "SECURITY.md", "docs/implementation-status.md"],
            "Audit product, setup, security, and milestone-status documentation against current source truth.",
        ),
        _track(
            "runtime-contracts",
            "coding",
            "explore",
            ["docs/architecture.md", "docs/runbook.md", "docs/artifact-lineage.md", "contracts/", "services/"],
            "Audit architecture, runbook, artifact-lineage, and runtime-contract documentation against implementation and tests.",
        ),
        _track(
            "agent-guidance",
            "routine",
            "agent-guidance-auditor",
            [
                "AGENTS.md",
                "CLAUDE.md",
                ".windsurfrules",
                ".cursor/",
                ".agents/",
                ".kilo/",
                ".github/",
            ],
            "Audit agent rules, skills, commands, workflows, and links for drift or contradictory delegation claims.",
        ),
        _track(
            "build-config",
            "coding",
            "explore",
            ["Makefile", "versions.env", ".github/workflows/", "infra/", ".kilo/"],
            "Audit build, CI, toolchain, coverage, and script claims against current files.",
        ),
    ],
    "code-review": [
        _track(
            "runtime-boundaries",
            "coding",
            "polyglot-reviewer",
            ["cmd/", "services/", "contracts/"],
            "Review service boundaries, contract-first behavior, protocol use, and concrete runtime regressions without editing.",
        ),
        _track(
            "integrity-concurrency",
            "critical",
            "explore",
            ["services/", "contracts/", "tests/", "docs/architecture.md"],
            "Review integrity rules, maturity ranks, artifact hashes, idempotency, retries, and concurrency claims without editing.",
        ),
        _track(
            "tests-docs-tooling",
            "routine",
            "docs-contract-auditor",
            ["tests/", "docs/", ".agents/", ".kilo/", "Makefile", ".github/"],
            "Review tests, documentation, build claims, and operator evidence for the requested change without editing.",
        ),
    ],
    "autonomous-code-optimizer": [
        _track(
            "static-security",
            "coding",
            "explore",
            ["services/", "cmd/", "contracts/", "scripts/"],
            "Perform a read-only Pass 1 scan for warnings, absolute paths, secrets, dead code, and static quality issues.",
        ),
        _track(
            "integrity-concurrency",
            "critical",
            "explore",
            ["services/", "tests/", "docs/architecture.md"],
            "Perform a read-only scan of integrity rules, idempotency, maturity ranks, artifact hashes, and retry invariants.",
        ),
        _track(
            "architecture-layers",
            "agentic",
            "explore",
            ["services/", "infra/", "contracts/", "docs/architecture.md"],
            "Perform a read-only architecture, layering, protocol-boundary, and contract-first scan using the owning architecture guidance.",
        ),
        _track(
            "tests-guidance",
            "routine",
            "docs-contract-auditor",
            ["tests/", "services/", ".agents/", "docs/"],
            "Perform a read-only scan for missing regression coverage, stale guidance, and verification gaps related to optimizer findings.",
        ),
    ],
    "continuous-quality": [
        _track(
            "runtime-edges",
            "critical",
            "explore",
            ["services/", "contracts/"],
            "Discover runtime, integrity-rule, persistence, and concurrency edge cases without editing.",
        ),
        _track(
            "tests-coverage",
            "coding",
            "explore",
            ["tests/", "services/"],
            "Discover missing tests, golden artifacts, and coverage gaps without editing.",
        ),
        _track(
            "integrity-flows",
            "agentic",
            "explore",
            ["services/run-orchestrator-kotlin/", "contracts/", "docs/architecture.md"],
            "Discover orchestration, SSE, Kafka, and state-transition regressions without editing.",
        ),
        _track(
            "anti-cheating",
            "coding",
            "explore",
            ["tests/anti-cheating/", "tests/"],
            "Discover anti-cheating suite gaps and assertion weaknesses without editing.",
        ),
    ],
    "continuous-improvement": [
        _track(
            "runtime-quality",
            "coding",
            "polyglot-reviewer",
            ["cmd/", "services/", "contracts/"],
            "Discover bounded code, boundary, integrity, and static-quality improvements without editing.",
        ),
        _track(
            "tests-acceptance",
            "critical",
            "explore",
            [
                "tests/",
                "services/",
                "docs/architecture.md",
                "docs/implementation-status.md",
            ],
            "Discover distinct test, anti-cheating, integration, e2e, and acceptance improvements without editing.",
        ),
        _track(
            "docs-guidance",
            "routine",
            "agent-guidance-auditor",
            [
                "docs/",
                "AGENTS.md",
                "CLAUDE.md",
                ".agents/",
                ".kilo/",
                ".github/",
                ".cursor/",
                ".windsurfrules",
            ],
            "Discover documentation, agent-guidance, screenshot, and workflow improvements without editing.",
        ),
        _track(
            "build-operations",
            "routine",
            "explore",
            ["Makefile", "versions.env", "scripts/", "infra/", ".github/workflows/"],
            "Discover dependency, build, CI, and local-operations improvements without editing.",
        ),
    ],
    "comprehensive-quality-overhaul": [
        _track(
            "runtime-integrity",
            "critical",
            "polyglot-reviewer",
            ["cmd/", "services/", "contracts/", "docs/architecture.md"],
            "Perform a broad read-only review of runtime behavior, protocol boundaries, provenance, and integrity rules.",
        ),
        _track(
            "tests-coverage",
            "coding",
            "explore",
            ["tests/", "services/", "Makefile"],
            "Review test independence, coverage, integration/e2e acceptance, and missing defect classes without editing.",
        ),
        _track(
            "docs-guidance",
            "routine",
            "agent-guidance-auditor",
            [
                "docs/",
                "AGENTS.md",
                "CLAUDE.md",
                ".agents/",
                ".kilo/",
                ".github/",
                ".cursor/",
                ".windsurfrules",
            ],
            "Review docs, skills, rules, harness projections, and screenshot claims for drift without editing.",
        ),
        _track(
            "build-operations",
            "routine",
            "explore",
            ["Makefile", "versions.env", "scripts/", "infra/", ".github/workflows/"],
            "Review dependencies, build scripts, CI, infrastructure, and local-acceptance operations without editing.",
        ),
        _track(
            "ui-architecture",
            "agentic",
            "explore",
            [
                "services/web-shell/",
                "services/artifact-inspector-ruby/",
                "web/",
                "docs/screenshots/",
                "docs/architecture.md",
            ],
            "Review browser-facing behavior, screenshot evidence, and architecture alternatives without booting or editing the stack.",
        ),
    ],
    "adversarial-pr-review": [
        _track(
            "runtime-correctness",
            "coding",
            "explore",
            ["services/", "contracts/"],
            "Review changed runtime behavior and direct source dependencies for concrete regressions.",
        ),
        _track(
            "integrity-rules",
            "critical",
            "polyglot-reviewer",
            ["services/", "docs/architecture.md"],
            "Review integrity-rule compliance, protocol claims, and artifact provenance in the changed hunks.",
        ),
        _track(
            "tooling-security",
            "agentic",
            "agent-guidance-auditor",
            [
                "AGENTS.md",
                "CLAUDE.md",
                ".windsurfrules",
                ".cursor/",
                ".kilo/",
                ".agents/",
                ".github/",
                "Makefile",
                "infra/",
            ],
            "Review changed tooling, permissions, credentials, configuration, and workflow safety claims.",
        ),
        _track(
            "tests-docs",
            "routine",
            "docs-contract-auditor",
            ["tests/", "docs/", "AGENTS.md"],
            "Review changed tests and documentation for contract gaps or misleading verification claims.",
        ),
    ],
    "ai-slop-detector": [
        _track(
            "production-build",
            "coding",
            "explore",
            ["services/", "cmd/", "contracts/", "Makefile"],
            "Audit production and build artifacts for needless complexity, invented integrations, and unprotected behavior.",
        ),
        _track(
            "tests",
            "coding",
            "explore",
            ["tests/", "services/"],
            "Audit tests for mirror coverage, dead assertions, and missing behavior protection.",
        ),
        _track(
            "docs-skills-rules",
            "routine",
            "agent-guidance-auditor",
            [
                "docs/",
                ".agents/",
                ".kilo/",
                "AGENTS.md",
                "CLAUDE.md",
                ".windsurfrules",
                ".cursor/",
                ".github/",
            ],
            "Audit documentation and agent artifacts for stale claims, dead instructions, and architecture drift.",
        ),
        _track(
            "contracts-generated",
            "coding",
            "explore",
            ["contracts/", "services/"],
            "Audit contracts and generated-code artifacts for invented APIs, hand-edited generated code, and schema drift.",
        ),
    ],
    "complex-code-comments": [
        _track(
            "backend-comments",
            "coding",
            "explore",
            ["services/", "cmd/"],
            "Find non-obvious service and protocol logic that needs a concise why-comment or has stale comments.",
        ),
        _track(
            "contracts-tests-comments",
            "routine",
            "docs-contract-auditor",
            ["contracts/", "tests/", ".agents/", "docs/"],
            "Find stale or noisy comments in tests and guidance without editing files.",
        ),
    ],
    "rules-and-skills-audit": [
        _track(
            "canonical-rules",
            "routine",
            "agent-guidance-auditor",
            ["AGENTS.md", ".kilo/operating.md"],
            "Audit canonical rules and always-on operating norms for conflicts and stale assumptions.",
        ),
        _track(
            "domain-skills",
            "routine",
            "agent-guidance-auditor",
            [".agents/skills/"],
            "Audit domain skills for routing, scope, safety, and code-contract drift.",
        ),
        _track(
            "harness",
            "routine",
            "agent-guidance-auditor",
            [".kilo/", "CLAUDE.md", ".windsurfrules", ".cursor/", ".github/"],
            "Audit Kilo commands, agents, scripts, and cross-file guidance links for drift.",
        ),
    ],
    "skill-reviewer": [
        _track(
            "domain-content",
            "agentic",
            "agent-guidance-auditor",
            [".agents/skills/"],
            "Review domain skill content for missing patterns, anti-patterns, and verification checklists.",
        ),
        _track(
            "workflow-content",
            "routine",
            "agent-guidance-auditor",
            [".agents/skills/parallel-multi-agent", ".agents/skills/continuous-quality", ".agents/skills/adversarial-pr-review"],
            "Review orchestration skills for coherent delegation, integration, and stop contracts.",
        ),
        _track(
            "harness-index",
            "routine",
            "agent-guidance-auditor",
            [
                "AGENTS.md",
                "CLAUDE.md",
                ".windsurfrules",
                ".cursor/",
                ".github/",
                ".kilo/operating.md",
                ".kilo/",
            ],
            "Review indexes and harness routing for drift and dead references.",
        ),
    ],
    "dependency-upgrade": [
        _track(
            "go-kotlin-java",
            "routine",
            "explore",
            ["cmd/", "services/vector-normalizer-go/", "services/run-orchestrator-kotlin/", "services/glyph-catalog-java/", "versions.env"],
            "Detect Go, Kotlin, Java, and JVM toolchain upgrade opportunities without editing.",
        ),
        _track(
            "cpp-dotnet-python",
            "routine",
            "explore",
            ["services/geometry-engine-cpp/", "services/rasterizer-dotnet/", "Directory.Packages.props", "services/image-pipeline-python/"],
            "Detect C++, .NET, and Python dependency upgrade opportunities without editing.",
        ),
        _track(
            "node-ruby-rust",
            "routine",
            "explore",
            ["services/ocr-worker-node/", "services/event-gateway-node/", "services/adjudicator-ruby/", "services/phrase-assembler-rust/", "rust-toolchain.toml"],
            "Detect Node, Ruby, and Rust dependency upgrade opportunities without editing.",
        ),
        _track(
            "infra-ci",
            "routine",
            "explore",
            ["versions.env", "infra/", ".github/workflows/"],
            "Detect container image, Helm chart, Terraform, and CI action upgrade opportunities without editing.",
        ),
    ],
    "architecture-review": [
        _track(
            "services-pipeline",
            "agentic",
            "explore",
            ["services/", "contracts/", "docs/architecture.md"],
            "Map the service graph, protocol boundaries, and artifact maturity path for alternatives.",
        ),
        _track(
            "infra-operations",
            "agentic",
            "explore",
            ["infra/", "scripts/", "Makefile", "docs/runbook.md"],
            "Map the acceptance stack, k3d topology, and operations architecture for alternatives.",
        ),
        _track(
            "security-guidance",
            "critical",
            "agent-guidance-auditor",
            [".agents/", ".kilo/", "SECURITY.md", "CONTRIBUTING.md"],
            "Map security, local-trust, and agent-harness architecture for alternatives.",
        ),
    ],
}


DISTINCT_ROUTE_WORKFLOWS = frozenset({"adversarial-pr-review", "documentation-adversarial-review"})


def requires_distinct_routes(workflow: str | None) -> bool:
    return workflow in DISTINCT_ROUTE_WORKFLOWS


def available_workflows() -> tuple[str, ...]:
    return tuple(sorted(WORKFLOW_TRACKS))


def build_tracks(workflow: str, parent_task: str) -> list[dict[str, Any]]:
    if workflow not in WORKFLOW_TRACKS:
        raise KeyError(workflow)
    return [
        {
            **track,
            "task": f"Parent request:\n{parent_task}\n\nTrack focus:\n{track['task']}",
        }
        for track in WORKFLOW_TRACKS[workflow]
    ]
