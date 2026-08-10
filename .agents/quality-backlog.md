# Quality backlog

Durable store for findings from [continuous-quality](../.agents/skills/continuous-quality/SKILL.md)
and other QA work, so nothing survives only in chat. Add dated entries under
the section that matches their state. **L** items (integrity rules, secrets,
cluster/infrastructure, public contracts) should also become GitHub issues
with labels once confirmed.

## Open

<!-- new findings go here: - [S|M|L] YYYY-MM-DD: finding — path — evidence -->

## In progress

<!-- being fixed -->

## Done

<!-- fixed and verified — keep the verification note -->

## Deferred

<!-- why: blocker, needs approval, too risky now -->

- [M] 2026-08-09: Java test runs report the terminally deprecated
  `sun.misc.Unsafe::objectFieldOffset` path from OpenTelemetry's shaded JCTools,
  plus Mockito's dynamically self-attached inline-mock-maker agent warning.
  The full pre-commit gate passes; this is dependency/test-runtime work rather
  than an application defect. Revisit on the next Java/OpenTelemetry/Mockito
  upgrade or before a JDK release that disables dynamic agent loading; prefer a
  supported dependency update or explicit test-agent configuration.
- [S] 2026-08-09: Artifact Inspector coverage reports Bundler/Ruby
  `Gem::Platform` constant redefinition warnings. Coverage passes at 95.34% and
  the warning is confined to the current Bundler/Ruby toolchain. Revisit during
  the next Ruby/Bundler dependency refresh and confirm the warning is gone.

## Dropped

<!-- why: invalid, superseded, not reproducible -->
