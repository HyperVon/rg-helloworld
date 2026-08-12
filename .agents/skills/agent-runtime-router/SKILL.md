---
name: agent-runtime-router
description: >-
  Use the installed Agent Runtime Router to inventory explicit provider/model
  evidence, make a fail-closed route decision, or build a digest-only dry-run
  plan. Use when routing a task, selecting a subagent candidate, inspecting
  denials or quota evidence, or checking why no route was eligible.
---

# Agent Runtime Router

Use the receipt-managed runner at
`.agents/.agent-runtime-router/run.py`. It executes the installed package from
the target-local isolated environment and does not depend on a personal source
checkout path.

## Commands

All inputs are explicit JSON files. Keep catalogs, tasks, policies, and
packets free of credentials and full prompts.

Validate a candidate catalog:

```text
python .agents/.agent-runtime-router/run.py inventory \
  --catalog <catalog.json> --pretty
```

Select one eligible candidate:

```text
python .agents/.agent-runtime-router/run.py route \
  --task <task.json> --catalog <catalog.json> --policy <policy.json> --pretty
```

Create a provider-neutral dry-run plan:

```text
python .agents/.agent-runtime-router/run.py plan \
  --task <task.json> --catalog <catalog.json> --policy <policy.json> \
  --packet <packet.json> --pretty
```

Exit status `0` means a usable result, `2` means no candidate was eligible,
and `64` means invalid input. Always inspect the JSON evidence, including every
candidate's rejection reasons and the ranking rule.

## Harness integration checks

When the target has an approved local harness integration, inspect its
secret-free profile and run an explicit bounded discovery source:

```text
python .agents/.agent-runtime-router/run.py harness profile \
  --target . --pretty
python .agents/.agent-runtime-router/run.py harness discover \
  --target . --config .agents/runtime-router/adapters/<id>/discovery.json \
  --pretty
python .agents/.agent-runtime-router/run.py harness verify \
  --target . --adapter <id> --dry-run --pretty
python .agents/.agent-runtime-router/run.py harness plan-adaptation \
  --target . --harness <new-id> \
  --output <temporary-adaptation-plan.json> --pretty
```

Discovery is no-mutation by default. Add `--cache-output <path>` only when the
approved workflow explicitly authorizes refreshing the target-local cache.
The command executes only the fixed argv or HTTPS allowlist declared by the
target adapter. Exit `3` means an adapter integration failure; it is distinct
from exit `2` for incomplete/no-route evidence.

To switch harnesses, review the emitted adaptation plan and apply only the
unchanged plan after separate approval:

```text
python .agents/.agent-runtime-router/run.py harness apply-adaptation \
  --target . --plan <temporary-adaptation-plan.json> --approve --pretty
```

The apply command promotes only the target-local verified profile/cache and
active pointer, preserves the previous adapter and routing denials, and writes
a digest-only receipt. Any drift requires a new plan.

For native launching, require the target adapter's `LaunchSpec` to pass
`bind_launch_spec()` before constructing an `ExecutionApproval`. This rejects
identity drift, environment overrides, and limit mismatches; the returned
`WorkerCommand.sha256` is the digest that approval must bind.

## Routing rules

- Denials and blacklist entries are hard constraints and override preferences,
  paid allowances, and availability claims.
- Unknown capability, context, availability, quota, freshness, and cost
  evidence remains rejected unless the corresponding policy switch explicitly
  permits that dimension.
- Never replace a pinned provider or model silently, infer mutable provider
  facts, or turn a dry-run plan into execution authority.
- If the result is `no route`, use the per-candidate reasons to identify the
  missing or denied evidence. Do not broaden the policy merely to make a route
  appear.

## Cross-project acceptance evidence

When another repository is used to validate this router:

1. Record the repository, user-designated ref or commit, and exact source
   files for the catalog and policy.
2. Reconstruct the complete resolved policy, including provider and candidate
   denials, then check both a permitted route and every relevant denied route.
3. Label reduced or hand-built inputs `SYNTHETIC`; they are useful for core
   regression tests but are not proof of consumer integration.
4. Keep consumer-specific configuration, prompts, fixtures, inventories, and
   migration plans outside this router checkout.

If any required source or denial evidence is incomplete, report the result as
`INCONCLUSIVE` and stop the compatibility claim rather than filling gaps from
memory or a partial fixture.

## Worker boundary

The installed package also exposes an explicit local-worker API. A worker start
requires a one-shot task-, candidate-, and absolute-command-bound approval and
remains local, argv-only, bounded, cancellable, and observable. Do not invoke it from a
routing request unless the user separately authorizes the specific local
command. Provider authentication, network dispatch, retries, worktrees, and
recovery remain outside this installed skill.
