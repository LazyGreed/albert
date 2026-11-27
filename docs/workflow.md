# Workflow

Quintet runs through native subagents. Denia is the default coordinator.
The name and communication style are customizable. Nora, Felix, Vera, and
Iris have fixed roles in both workflows.

## Select a workflow

Use the installer's **Workflow** selector or pass `--workflow v1` or
`--workflow v2`. The installer defaults to `v2`. Rerun it at the same scope
and restart the harness to switch. Each managed block contains the shared
contract, one workflow, and the coordinator personality.

For each harness, the project workflow takes precedence over the global
workflow when both are loaded.

| Harness | Project instructions | Global instructions |
| --- | --- | --- |
| Pi | `PROJECT/AGENTS.md` | `~/.pi/agent/AGENTS.md` |
| Claude Code | `PROJECT/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| Antigravity CLI | `PROJECT/.agents/rules/AGENTS.md` | `rules/AGENTS.md` |
| Codex | `PROJECT/AGENTS.md` | `${CODEX_HOME:-~/.codex}/AGENTS.md` |

Pi honors `$PI_CODING_AGENT_DIR/AGENTS.md` when configured. Antigravity's
global `rules/AGENTS.md` is inside `~/.gemini/config/plugins/quintet`.
Codex project agents live in `PROJECT/.codex/agents`, with skills in
`PROJECT/.agents/skills`. Global Codex installs put `agents/` and `skills/`
under `${CODEX_HOME:-~/.codex}`. Project Codex and Pi share
`PROJECT/AGENTS.md`. Codex requires project trust to load
project-local agents. The installer preserves the existing trust settings.

When working directly in Quintet with no project installation, the root
[AGENTS.md](../AGENTS.md) points to the default [v2 workflow](../workflows/v2.md).
The coordinator puts `WORKFLOW: v1` or `WORKFLOW: v2` in workstream briefs so
Felix and Vera use the task's evidence rules even if both scopes are loaded.

## Task flow

1. Define the outcome and one observable acceptance condition.
2. Use Nora to resolve a concrete missing fact or prerequisite when needed.
3. Assign bounded implementation to Felix. The coordinator handles authorized
   Git operations. Workers never delegate.
4. Use Vera for independent review of consequential changes. Use Iris for
   meaningful user-facing acceptance or smoke checks.
5. Report `DONE`, `PARTIAL`, or `BLOCKED` with observed results. Mark unrun
   checks `NOT RUN`.

Both workflows use risk-based review for routine single-stream work. For
parallel work, give each writer exclusive ownership and an isolated native
checkout. Assign shared and planned files, including lockfiles and generated
outputs, to one writer or serialize. A worker that needs an unowned path
reports it to the coordinator.

Every parallel or v2 graph stream needs a mechanical ownership check and a
separate Vera `PASS` on the diff and its acceptance evidence before landing
on the task integration branch. Use
`skills/verification/scripts/check-ownership.sh` to check changed and untracked
paths. Read-only specialists can verify checkout integrity with
`skills/verification/scripts/check-readonly.sh`. Run a separate combined check
after the streams land.

## v1 coordinator sequencing

Name the required handoff in `DEPENDENCIES`. Denia schedules the dependent
work once the handoff is available and updates affected briefs if it changes.
Felix identifies the actual diff or worktree. Vera independently reviews
that evidence, which can include an uncommitted diff. Denia verifies each
parallel stream before integration and runs the separate combined check
after landing. [v1 instructions](../workflows/v1.md)

An example provider brief follows.

```text
WORKFLOW: v1
STREAM: api
INSTANCE/ROLE: felix-api / felix
GOAL: Return stable validation errors
WRITE OWNERSHIP: server/validation/**, tests/validation/**
DO NOT EDIT: server/routes/**, shared/config/**
CHECKOUT: verified isolated worktree/branch
ACCEPT: valid input succeeds, invalid input returns documented fields
CHECKS: focused API tests and an error-path regression
DEPENDENCIES: none; hand off the verified error fields to the UI stream
VERIFIER: vera-api / vera
```

## Dependency graph

In v2, Denia uses one directed acyclic graph (DAG) for two or more
implementation streams or when a verified stream changes. Edges point from
provider or writer to dependent or reader. Use `DEPENDENCIES` for hard
inputs and `READS` for narrow paths outside write ownership. Add `REF` once
Felix reports it. [v2 instructions](../workflows/v2.md)

A v2 consumer brief can name a hard prerequisite and a read-only contract.

```text
WORKFLOW: v2
STREAM: ui
INSTANCE/ROLE: felix-ui / felix
GOAL: Display the documented validation error
WRITE OWNERSHIP: ui/validation/**, tests/ui/**
DO NOT EDIT: server/**, shared/**
CHECKOUT: verified clean and isolated worktree/branch
ACCEPT: failed validation renders the error field, success has no error
CHECKS: focused UI checks for both paths
DEPENDENCIES: api (current verified ref)
READS: shared/schema/**
VERIFIER: vera-ui / vera
REF: wt/ui@<sha> (once Felix reports)
```

### Ready, invalidate, and join

1. **Ready.** Check dependency order, writer isolation and ownership, and the
   evidence needed to start each stream. Serialize overlapping readers and
   writers unless the speculative-reader conditions are met.
2. **Invalidate.** Recheck stream evidence before landing. A change can
   invalidate a hard input binding or affect a declared read scope. Vera
   re-verifies stale evidence against the intended inputs. Felix edits when
   the recheck finds a defect.
3. **Join.** Test the landed streams together on a clean integration branch.
   Bind the result to the revisions tested and recheck the binding before
   final merge. Route join fixes to the responsible writer.

Use the [v2 workflow](../workflows/v2.md) for the exact gate commands, input
schema, and evidence requirements.

For example, if API stream `a1` fails and Felix fixes it at `a2`, consumer
`b1` can be re-verified in a clean checkout combining `a2` and `b1`. When the
trial passes, keep `b1` and carry its new evidence into the join. An unrelated
stream keeps its verdict if its inputs are still current.

On resume, derive `pending`, `dispatched`, `reported`, `verified`, `stale`,
`abandoned`, or `landed` from native sessions, Git, and verdicts. Skip unstarted
work and keep abandoned worktrees. Use an existing issue or PR for durable
status when needed.

## Blockers and recovery

| Blocker | Action |
| --- | --- |
| Missing evidence or contract | Ask Nora the narrow question |
| Implementation defect | Assign Felix the fix and focused checks |
| Missing tool, access, or permission | Inspect and report the blocker |
| User-only decision or authority boundary | Ask the user |

Allow up to two automatic Felix edit plus Vera re-review rounds across the
task, including integration fixes. In v2, clean trial rechecks alone use no
round. At the cap, report failed checks and the next action. In v2, include
stale streams, refs, and worktree paths. Never retry an unchanged failing
approach or weaken a check.

## Specialized skills

[Alien Science Ideation](../skills/alien-science-ideation/SKILL.md) requires an
explicit request for alien science, alien ideation, cognitively unavailable
research directions, or the skill. The worker brief must confirm the request.

The [weight-space audit skill](../skills/weight-space-network-audit/SKILL.md)
has three activation modes.

- [skills/weight-space-network-audit/references/relu-audit.md](../skills/weight-space-network-audit/references/relu-audit.md)
  is the specialized path for small feed-forward ReLU decision networks with
  accessible weights and an explicit protocol.
- `AUDIT_ONLY` inspects checkpoints without editing weights.
- `AUTO_IMPROVE`, `DIRECT_ONLY`, and `RESEARCH` require an explicit request for
  model improvement or the universal methodology. Authorized reversible edits
  use safe copies only.

Test behavior against the protocol. Independently check candidate deviations,
collateral regressions, and deployment precision. Preserve original artifacts,
report sampling limits, and get separate authorization for deployment.

## v2 evaluation

The benchmark has offline fixtures and a trial plan. The live comparison is
pending.

### Benchmark configuration

Use a clean source worktree pinned to its full commit SHA. Set `MODEL` to the
same pinned Claude model for both variants and `BUDGET` to the approved USD
limit per invocation. The plan validates the source and lists the trial order
and budget ceiling without starting Claude Code.

```sh
SOURCE=/absolute/path/to/pinned/quintet-worktree
REVISION=$(git -C "$SOURCE" rev-parse HEAD)
python3 tests/live-graph.py --self-test
python3 tests/live-graph.py --plan --same-revision --q1 "$SOURCE" \
  --q1-sha "$REVISION" --model "$MODEL" --budget "$BUDGET" --trials 5 --timeout 600
```

An authorized live run uses the same arguments with `--live` in place of
`--plan` and `--out` pointing to a new directory outside the runner and every
source worktree.

```sh
python3 tests/live-graph.py --live --same-revision --q1 "$SOURCE" \
  --q1-sha "$REVISION" --model "$MODEL" --budget "$BUDGET" --trials 5 --timeout 600 \
  --out /absolute/path/to/new-benchmark-output
```

Each scenario uses paired runs in fresh fixture repos. Odd trials run v1 first
and even trials run v2 first. The installer selects the workflow explicitly
from the same revision. The Claude Code model, permissions, timeout, invocation
budget, prompts, and fixture tasks match within each pair. Both installs use
`--no-web`. S3 and S5b allow up to two invocations per trial and S5 up to three.
All other scenarios allow one. Run at least five pairs per scenario for the
scenario gates below. Keep `plan.json`, fixture repos, raw JSONL and stderr,
checkpoint snapshots, `timing.json`, and `result.json` together. Live plans
record the Claude Code version and the benchmark script hash.

For the historical comparison, omit `--same-revision`, pass `--q0` at
`6715d8d52a1d69480be2f2bec778184fb7abd3cf`, and pin the Q1 source with `--q1`
and `--q1-sha`. Both historical installs use the defaults at their own sources.
Q1 must be a strict descendant of Q0 by default. `--allow-diverged-q0` accepts
sources with a shared merge base and records that base.

### Scenario gates

The reference is v1 for same-revision trials and Q0 for historical trials.

- **S1.** Accepted single-stream fix, zero extra workers, exact static tokens
  at most the reference, and median runtime tokens at most 115% of the reference.
- **S2.** No regression in accepted completion or worker count for disjoint
  parallel streams.
- **S3.** Improve clean invalidation by at least two of five trials, or pass
  at least four of five if the reference passes two or fewer. A tie qualifies when it
  cuts unnecessary consumer calls. Evidence covers the initial API failure,
  passing fix, and final binding.
- **S4.** Reduce ownership violations, targeting zero in at least four of five
  trials. Audit reflog transitions and attributable patches. Exclude imported
  paths from ownership violations.
- **S5.** Zero stale or dirty landings and strictly fewer unsupported completion
  claims. Inspect snapshots before mutation and landing.
- **S5b.** Diagnose a semantic join failure and route it within two rounds using
  refreshed inputs. Pause at the first join to test the exact joined commits.

### Recorded metrics

| Metric | Measurement |
| --- | --- |
| Accepted completion | The final reply claims completion, the runner's hidden check passes on the integration commit, required worker tips are ancestors, the base is unchanged, observed worktrees and the integration worktree are clean, and the applicable ownership checks pass. Evaluate the scenario gates separately. |
| Native turn tokens | Sum input, output, cache creation, and cache read tokens from each invocation's terminal usage record. Missing usage gives `null`. The provider's aggregate has no verified coordinator or worker split. |
| Wall latency | Monotonic elapsed time from immediately before the first Claude Code invocation to the return of the last, including pauses and runner checkpoints between them. Fixture setup, installation, and final scoring are outside the interval. An interrupted trial with timing evidence is marked censored. |
| Unnecessary dispatches | Count identifiable `Agent` or `Task` launches with identical inputs in the same assistant tool batch after the first. Resumes and repeated tool IDs are excluded. Each invocation needs an assistant trace with well-formed tool calls. Missing or malformed trace evidence gives `null`. Other redundant work and nested attribution need trace review. |
| Ownership violations | The runner's checker lists out-of-scope changes in observable worker patches, the final integration patch, and dirty worktrees available at scoring. S4 also uses reflogs to attribute writes and detect shared writers. Incomplete attribution gives `null` when no violation can be established. A nonempty list can be a lower bound. |
| Supplied stale evidence | Count verdict rows whose supplied refs resolve to commits that differ from the refs in the corresponding runner snapshot. Unresolved refs or missing bindings are unsupported fields. Without a confirmed mismatch, missing or incomplete evidence gives `null`. A matching tuple leaves independent verifier provenance unknown. |
| Unsupported completion claim | Count one when the final reply claims completion and the runner cannot accept it. Explicit completion requires one `BENCHMARK_OUTCOME COMPLETE` at the end of the reply. Without a marker, the runner checks the leading legacy status. Blockers, refusals, and partial outcomes count zero. Duplicate, contradictory, malformed, or missing outcome evidence gives `null`. |

Report raw observations, paired differences and medians once live trials exist.
Show sample sizes and unknown counts for each metric, and keep censored latency
separate. Landing-time cleanliness, verifier provenance, exact rendered token
counts, and nested or reused work need separate evidence. Reflogs can miss
uncommitted writes or rewritten history. Across S1 through S5, compare
unsupported completion, observed ownership violations, and unnecessary launches
against the reference variant. Keep the optional overlap helper and experiment
branches deferred until S4 or S5b shows a collision or rework the existing
workflow misses.

## Harness notes

- See the [README installation instructions](../README.md#install) for tested
  Pi prerequisites and package requirements.
- See [Read-only verification](read-only-verification.md) for tested native
  restrictions and snapshot checks.
- Use native peer messaging only when the host exposes it. Otherwise relay
  through the coordinator. [Peer messaging by harness](peer-messaging.md)
- Background work may stop when the parent session exits. Check native state
  on resume. Push, final target merges, production deployment, irreversible
  cleanup, and credential or permission changes need explicit approval.
  [Shared coordinator contract](../AGENTS.md)
