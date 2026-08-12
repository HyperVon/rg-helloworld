---
name: agent-runtime-router-maintenance
description: >-
  Audit, refresh, or repair an Agent Runtime Router installation using its
  receipt, ignored source locator, and current local checkout. Use when the
  router needs updating, its source path changed, an installation is missing
  or drifted, or a target project's router setup should be verified.
---

# Agent Runtime Router Maintenance

Use this skill after bootstrap. It owns the installed router's source
resolution, receipt-aware refresh, route validation, and drift reporting. It
does not silently overwrite locally modified skills or runtime state.

## Resolve the source

Run the bundled resolver from the target repository:

```text
python .agents/skills/agent-runtime-router-maintenance/scripts/resolve_source.py \
  resolve --target .
```

Resolution order is:

1. an explicit `--router-root` for this invocation;
2. `AGENT_RUNTIME_ROUTER_ROOT` in the environment;
3. the ignored `.agents/.agent-runtime-router/source.json` locator;
4. a validated adjacent `agent-runtime-router` sibling.

If none resolves, stop and ask for the checkout path. Do not search unrelated
directories or fetch a replacement.

## Audit and refresh

1. Read target guidance and the current receipt at
   `.agents/.agent-runtime-router/receipt.json`.
2. Validate the current installation:

   ```text
   python .agents/skills/agent-runtime-router-maintenance/scripts/validate_installation.py \
     --target .
   ```

3. Generate a new read-only plan from the resolved source:

   ```text
   python <router-root>/.agents/skills/bootstrap-runtime-router/scripts/install_runtime.py \
     plan --router-root <router-root> --target . --output <temporary-plan.json>
   ```

4. Review source revision, package digest, skill statuses, route changes, and
   conflicts. Obtain explicit approval for that exact plan.
5. Apply only the unchanged approved plan:

   ```text
 python <router-root>/.agents/skills/bootstrap-runtime-router/scripts/install_runtime.py \
   apply --router-root <router-root> --target . \
   --plan <temporary-plan.json> --approve
```

## Harness audit and refresh

If the target has a target-owned harness profile and adapter configuration,
inspect them after the mechanical installation refresh:

```text
python .agents/.agent-runtime-router/run.py harness profile \
  --target . --pretty
python .agents/.agent-runtime-router/run.py harness discover \
  --target . --config .agents/runtime-router/adapters/<id>/discovery.json \
  --pretty
python .agents/.agent-runtime-router/run.py harness verify \
  --target . --adapter <id> --dry-run --pretty
python .agents/.agent-runtime-router/run.py harness audit \
  --target . --pretty
python .agents/.agent-runtime-router/run.py harness plan-adaptation \
  --target . --harness <new-id> \
  --output <temporary-adaptation-plan.json> --pretty
```

These commands do not switch harnesses or mutate policy. A cache refresh must
be separately approved and explicitly use `--cache-output`; adapter failures
remain distinct from a no-route result. Review a `READY_FOR_REVIEW` adaptation
plan, then apply only that unchanged plan with a separate approval:

```text
python .agents/.agent-runtime-router/run.py harness apply-adaptation \
  --target . --plan <temporary-adaptation-plan.json> --approve --pretty
```

The apply step promotes only the requested verified profile/cache and active
pointer, preserves the previous adapter and target denials, records a
secret-free receipt, and fails closed on any drift. Semantic adapter changes
still require target-local edits and a new discovery/verification plan.

`harness verify --dry-run` checks the active profile and target-owned
`adapters/<id>/adapter.json` plus `discovery.json` metadata. It does not import
or execute target adapter code.

Use `harness audit` as the evidence snapshot for active harness, policy digest,
blacklist/task-profile counts, cache freshness, source digest, and fallback
state. It is read-only and prints no candidate contents.
Use `plan-adaptation` before a harness switch; it preserves the current adapter
and policy, and reports `INCOMPLETE` when the requested adapter lacks a
verified profile or fresh cache. Do not switch the active pointer as part of a
mechanical maintenance refresh.

To inventory a semantic harness adaptation without changing the target, resolve
the source and run the bootstrap helper's separate plan phase:

```text
python <router-root>/.agents/skills/bootstrap-runtime-router/scripts/install_runtime.py \
  integration-plan --router-root <router-root> --target . \
  --output <temporary-integration-plan.json>
```

Treat `INCOMPLETE` as an explicit missing-profile/adapter decision, not as
permission to infer providers or copy a catalog.

The helper refreshes only receipt-owned content whose current digest still
matches the prior receipt. A locally changed skill, route block, source
locator, runtime package, or runtime runner is a conflict and must be resolved
explicitly.

## Boundaries

- Never read or copy credentials, provider configuration secrets, prompts, or
  runtime data.
- Never install globally, modify the target's application dependency files, or
  contact package indexes or providers.
- Do not delete or silently repair a divergent installation. Report the exact
  conflict and stop.
- After refresh, verify the receipt, route, skill manifests, source locator,
  and `python .agents/.agent-runtime-router/run.py --version`.
