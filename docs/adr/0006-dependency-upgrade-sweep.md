# ADR-0006: 2026 dependency upgrade sweep

- Status: Accepted
- Date: 2026-08-05

## Context

Every reproducible pin in the repository (toolchains, frameworks, CI
actions, Terraform providers) was inventoried against current stable
releases. The sweep upgrades the following, one major change per group:

- Java stack: Spring Boot 3.5.3 -> 4.1.0, Spring WS 4.0.13 -> 5.0.2,
  Surefire 3.5.2 -> 3.5.6, runtime/toolchain JDK 21 -> 25 (Temurin).
  Spring WS 5.0.2 requires Spring Framework 7 / Boot 4.x, so the two
  jump together. Compiler release and Kotlin `jvmTarget` stay at 21
  (compatibility setting, not a pin).
- Kotlin runtime: Lettuce 6.7.1.RELEASE -> 7.6.0.RELEASE, ktlint CLI
  1.7.1 -> 1.8.0 (Gradle plugin stays 14.2.0).
- Node: TypeScript 5.9.3 -> 7.0.2, Node 24.19.0 -> 26.6.0 (CI and
  `.nvmrc`-managed toolchain).
- Python: 3.13 -> 3.14 (ruff `target-version` py313 -> py314).
- Ruby: 3.4 -> 4.0 (CI and versions.env).
- CI: all 9 GitHub Actions bumped to latest with full SHA-256 pins.
- Terraform: provider `helm` 2.11.0 -> 3.2.0, `kubernetes` 3.1.0 ->
  3.2.1, `kubectl` 1.17.0 -> 1.19.0.

Maven stays 3.9.16 (3.10.0-rc-1 is a pre-release). No floating
`latest` tags are introduced anywhere.

## Decision

Adopt the upgraded pins listed above. The Terraform `helm` provider
v3 upgrade rewrites the `kubernetes` block to the nested-object form
and converts `set {}` blocks to `set = [...]` list attributes; a
`terraform plan` after `terraform init -upgrade` confirms the SDKv2 ->
Plugin Framework state migration is in-place (0 to add, 0 to destroy,
4 in-place metadata refreshes) with identical value sets.

## Consequences

- Dockerfiles and CI use Temurin 25 for build and runtime; Java
  language level remains 21 for source compatibility.
- The Helm provider migration touched the live `terraform.tfstate`; the
  post-upgrade e2e infra step re-applied it (`terraform apply`: 0 added,
  4 changed, 0 destroyed) to bring state in line with the v3 schema.
- `set` attributes are now lists of objects; future chart-value
  edits must follow the list form.
- Kubernetes provider emits pre-existing deprecation warnings
  (`kubernetes_namespace` -> `kubernetes_namespace_v1`); migrating
  those resources is tracked separately to keep this sweep scoped.
- Lockfiles (`package-lock.json`, `requirements-dev.txt`,
  `Gemfile.lock`) and `versions.env` are the single source of truth
  for the new pins; the skeleton table in
  `docs/implementation-status.md` reflects the new toolchains.
