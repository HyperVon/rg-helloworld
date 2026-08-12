# Agent Runtime Router and Kilo

This repository's application does not use Agent Runtime Router. The target-
owned Kilo integration is only for human-approved agent-development work.

## Discovery

The adapter resolves Kilo 7.4.21 to an absolute executable and performs a
bounded, shell-free discovery. It uses `kilo models --verbose` when that flag is
advertised. Kilo emits one identifier followed by one JSON metadata object per
model; the adapter validates the identity match and records only structured ARR
fields. The table path remains available for Kilo versions that do not expose
verbose metadata.

Refresh the ignored local cache with an explicit candidate bound:

```text
python .agents/.agent-runtime-router/run.py harness discover \
  --target . \
  --config .agents/runtime-router/adapters/kilo/discovery.json \
  --max-candidates 1000 \
  --cache-ttl 3600 \
  --cache-output .agents/runtime-router/catalog-cache.json \
  --pretty
```

The explicit candidate bound is required because Kilo currently lists more than
ARR's generic default of 500 candidates. The target uses a one-hour cache TTL:
long enough to avoid repeating the expensive 846-model/quota discovery during a
work session while still refreshing provider quota regularly. The generated
cache and diagnostic report are ignored and must never be committed.

Verbose metadata currently proves model identity, catalog status, cost class,
context window, and selected capabilities. It does not prove account quota.
When the local `@slkiser/opencode-quota` package is installed, the generated
discovery command also performs a bounded, secret-redacted quota refresh and
joins provider-level remaining percentages to the catalog. It never copies or
prints OpenCode/Kilo credentials. Expired authentication, provider errors, and
missing quota remain `blocked`/`unknown`; they are never treated as available.

The target policy keeps `allow_unknown_quota` false for paid/account-priced
models. ARR preserves the old router's rule that a free model whose provider
does not expose a meter may remain eligible, while an explicitly blocked or
exhausted model is still rejected. This means a usable free route can be
selected without silently opting paid routes into unknown quota.

The target-owned blacklist preserves the removed router's safety denials:
Claude/Anthropic models, Minimax models, `gpt-5-6-sol`, and the two explicitly
blocked NVIDIA model IDs. Glob patterns are target policy entries and are
applied before ARR ranking.

Keep these denials as target-owned glob entries. Current ARR 1.4.x accepts and
matches safe blacklist globs; do not expand them into a brittle list of every
currently observed model ID. If an older installed runtime rejects the policy,
refresh the receipt-managed runtime with the current ARR checkout and rerun
validation instead of weakening or rewriting the deny set.

The old router's provider list was a direct-provider configuration. Kilo's
native catalog is an aggregator and exposes additional Gateway model IDs, so
this integration deliberately keeps the observed Kilo catalog rather than
silently translating the old `kilo-auto/efficient` include rule. The old
blacklist remains enforced; add an explicit target allowlist before using this
integration where exact old-provider scope is required.

The generator records absolute machine-local Node and plugin paths in the
ignored `kilo-resolved.json` and `discovery.json`; do not commit those files.
If the plugin is absent, discovery still produces the model catalog while
leaving quota unknown; paid routes remain ineligible. Non-zero, stale, or
malformed plugin output is never promoted to available quota evidence.

## Verification

```text
python .agents/.agent-runtime-router/run.py harness audit --target . --pretty
python .agents/.agent-runtime-router/run.py --python \
  .agents/runtime-router/adapters/kilo/gen_discovery.py
python .agents/.agent-runtime-router/run.py --python \
  .agents/runtime-router/adapters/kilo/test_launch_dryrun.py
```

Run `gen_discovery.py` once per machine (and after Kilo is upgraded) before
adapter tests or discovery. It performs only the local Kilo version check and
writes ignored machine-local resolution files; it does not list models or
contact a provider. Always use the target-local runner's `--python` form for
adapter scripts. It uses the ARR version installed in this target's ignored
runtime and prevents a different global `agent-runtime-router` installation
from being imported.

Before any real task, plan several independent routes without contacting a
provider:

```text
python .agents/.agent-runtime-router/run.py --python \
  .agents/runtime-router/adapters/kilo/route_subagents.py --pretty
```

This reports one route for each target workstream and does not start workers.
When enough eligible candidates exist, each workstream receives a distinct
candidate; a later workstream may be `NO_ROUTE` rather than silently reusing a
previous selection. Any `--policy` or `--cache` override must resolve inside
the target checkout, preserving target ownership of routing state.
The workstream labels (`architecture-review`, `security-review`, and so on)
are local task labels; Kilo's `--agent` labels are not ARR capabilities. The
adapter's evidenced baseline is `chat`, with `reasoning` required only for the
two analysis roles. A missing or unusable cache returns structured
`INCOMPLETE` output and exit code 2, rather than a traceback. Review the routes
before selecting an approval-gated task command. This route plan is not a
repository-aware coding run; use an explicitly reviewed workspace snapshot for
that purpose.

The quota plugin reads OpenAI's OAuth entry from OpenCode's credential store,
not automatically from Kilo's separate credential store. Refresh the OpenCode
entry interactively with the OpenCode CLI:

```text
opencode auth login --provider openai
```

Only use `kilo auth login --provider openai` instead if you have verified that
your Kilo installation shares OpenCode's credential store; on installations
with separate stores it will not repair the quota plugin. After login, rerun
discovery; do not put the token in this repository or in any ARR file. If the
login flow offers multiple methods, choose the OpenAI OAuth method rather than
entering an API token into a project file.

The launch test validates the target-owned adapter's absolute, shell-free Kilo
command shape. It does not launch Kilo or send a provider task. To run one
ARR-managed task, first render the plan without execution:

```text
python .agents/.agent-runtime-router/run.py --python \
  .agents/runtime-router/adapters/kilo/run_arr_task.py \
  "Reply with exactly: ARR smoke test passed."
```

Review the selected route, then repeat the exact command with `--approve`.
This smoke runner uses an empty disposable workspace, binds the prompt and
selected candidate into ARR's approval digest, and supervises Kilo with bounded
output. It deliberately does not copy the target's dependency-heavy worktree.
For a real coding task, add a separately reviewed snapshot/workspace runner
before exposing repository files to a provider. Native launch remains
explicitly approval-gated; do not add credentials or raw provider output to
repository files.
