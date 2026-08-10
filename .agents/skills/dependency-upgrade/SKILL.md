---
name: dependency-upgrade
description: >-
  Upgrade pinned dependencies safely — security alerts first, version
  inventory across all languages, risk-grouped bumps, and full-gate
  verification. Use when the user asks to update dependencies, bump versions,
  refresh lockfiles, or address dependency/security alerts in this
  multi-language repository.
---

# Dependency Upgrade

This repository pins every dependency and container version (`versions.env`,
per-language lockfiles, Helm chart pins). Never use floating `latest` tags.
Upgrade in risk-ordered, reviewable groups; verify with the full gates after
each group.

## Step 1 — Security alerts first

```bash
gh api repos/{owner}/{repo}/dependabot/alerts --jq \
  '.[] | select(.state == "open") | [.number, .security_advisory.severity, .dependency.package.name, .dependency.manifest_path, (.security_vulnerability.vulnerable_version_range // "?")] | @tsv'
```

- Fix `critical` and `high` alerts promptly; track unfixable ones in the
  backlog with the blocker.
- An alert is evidence of a vulnerable range, not of a fixed version —
  confirm the patched version exists and matches the manifest before bumping.
- Never delete a security pin to make the build pass.

## Step 2 — Version inventory

Build a complete inventory before touching anything. Per-language anchors:

| Ecosystem | Manifest / lockfile |
| :--- | :--- |
| Go | `cmd/rghw/go.mod`, `services/vector-normalizer-go/go.mod` (+ `go.sum`) |
| Kotlin | `services/run-orchestrator-kotlin/build.gradle.kts` |
| Java | `services/glyph-catalog-java/pom.xml` |
| C++ | `services/geometry-engine-cpp/CMakeLists.txt` |
| C#/.NET | `services/rasterizer-dotnet/*.csproj`, root `Directory.Packages.props` |
| Python | `services/image-pipeline-python/pyproject.toml` |
| Node/TS | `services/*-node/package.json` + `package-lock.json` |
| Ruby | `services/adjudicator-ruby/Gemfile.lock` |
| Rust | `services/phrase-assembler-rust/Cargo.lock`, `rust-toolchain.toml` |

Shared pins: `versions.env` (container/toolchain versions), `infra/helm-charts/`
and `infra/helm-values/` (image tags), `infra/terraform/` (provider/module
versions), `.github/workflows/*` (action tags, pinned to full SHAs).

Record the current versions and the date. Version strings never prove
compatibility — read the release notes / migration guide for the target
version and record the source.

## Step 3 — Plan by risk

- **Patch/minor**: group into one coherent change set per ecosystem; update
  the lockfile and `versions.env` together.
- **Major**: one dependency per change; read its migration guide first;
  expect per-language breaking changes (`@Deprecated(replaceWith=...)`,
  `deprecation` warnings, removed APIs).
- **Container/images**: bump `versions.env` and the Helm values pin together;
  verify the image tag exists before pinning.

Anti-patterns: pre-releases, partial family bumps (e.g. one Jackson module),
upgrading to silence a warning without understanding it, mixing unrelated
upgrades in one commit.

## Step 4 — Apply and verify

1. Apply one group. Refresh the dependency state through the repository's own
   tooling (`make prerequisites` re-installs per-language deps).
2. Let the strict linter surface deprecations (`make lint` with `STRICT=1`);
   migrate against the official docs, not by silencing warnings.
3. Run the full gates serially: `STRICT=1 make prerequisites`,
   `STRICT=1 make format`, `STRICT=1 make lint`, `STRICT=1 make unit`,
   `STRICT=1 make coverage`, `STRICT=1 make build`. Add `make integration` /
   `make e2e` when container images or cross-service contracts changed.
4. One failure → revert the single bump, not the group; re-run.

## Step 5 — Docs and commit

- Update `versions.env`, per-language lockfiles, `README.md` stack table, and
  `AGENTS.md` stack pins in the same change.
- Record the upgrade in `docs/implementation-status.md` (and an ADR when the
  bump changes behavior).
- Commit each group as one coherent change via
  [commit-and-push](../commit-and-push/SKILL.md).

## Checklist

- [ ] Security alerts triaged first; patched versions confirmed
- [ ] Complete inventory taken (all 9 ecosystems + shared pins)
- [ ] Bumps grouped by risk; majors handled individually with migration guides
- [ ] `versions.env`, lockfiles, Helm values, and workflows updated together
- [ ] Full gates green with `STRICT=1`; no `latest` tags introduced
- [ ] Docs/status/stack pins updated in the same change
