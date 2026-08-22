# Contributing

Thanks for considering a contribution to Rube Goldberg Hello World.

## Repository state

The project is milestone-driven. Before opening an issue or PR, read:

- `docs/architecture.md` — the authoritative design (including the
  non-negotiable anti-cheating boundaries in section 7).
- `docs/implementation-status.md` — what is implemented and what is next.

## Development setup

```bash
make setup          # one-time: install missing toolchains + infra (Linux/macOS), then verify
make prerequisites   # checks toolchains and prepares language dependencies
make format          # format all languages
make lint            # lint all languages
make unit            # unit tests
make coverage        # unit tests with 90% coverage gates
make build           # compile everything
```

Set `STRICT=1` to fail on missing toolchains instead of skipping.

## Rules

- Implement one milestone at a time; do not jump ahead of the sequence in
  `docs/architecture.md` section 29.
- Pin every dependency and container version; never use floating `latest`
  tags.
- Do not combine service languages; do not bypass required protocols.
- Never leak the requested plaintext downstream of glyph planning.
- Keep code idiomatic and readable; the per-language linters and formatters
  must pass.
- Add or update tests with every change; keep coverage at 90% or higher
  where tooling supports it.

## Pull requests

- One coherent change per PR, matching a milestone step.
- CI must pass (`.github/workflows/ci.yml` runs format checks, lint, unit
  tests, coverage gates, and builds for every language).
- Update `docs/implementation-status.md` and the relevant service READMEs.
- Record architecture changes as ADRs under `docs/adr/`.
