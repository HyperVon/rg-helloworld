# ADR-0010: Free and open-source licenses only

- Status: Accepted
- Date: 2026-08-06

## Context

The Rube Goldberg Hello World project runs entirely on a single laptop
with no paid services, external APIs, or commercial infrastructure.
All dependencies must be free and open-source to align with this
constraint and to ensure the project remains reproducible without
licensing costs or legal risk.

## Decision

All dependencies used by this project must be licensed under a
**free and open-source license** (OSI-approved or equivalent).
Acceptable licenses include:

- MIT
- Apache-2.0
- BSD-2-Clause / BSD-3-Clause
- ISC
- MPL-2.0
- LGPL-2.1 / LGPL-3.0
- MPL-2.0 (with linking exception)
- CC0 / CC-BY
- Unlicense
- Public Domain

Licenses that require a commercial license, attribution-only terms
that conflict with the project's goals, or licenses that impose
royalty/fee obligations are **not permitted**.

## Consequences

- New dependencies must be vetted for license compatibility before
  being added.
- If a dependency's license changes to a non-free license, it must be
  replaced or removed immediately.
- The `versions.env` file must record the license type for each
  dependency that has a non-MIT license.
- CI lint checks should flag any newly introduced non-free-license
  dependency.
- The project avoids dependencies like SixLabors.ImageSharp 4.x
  (which requires a commercial license key) and uses only
  MIT-licensed alternatives or older free-license versions.
- No paid SaaS, API keys, or commercial runtimes are used.
