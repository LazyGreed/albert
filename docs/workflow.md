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
Codex project agents live in `PROJECT/.codex/agents`. Global Codex agents live
in `${CODEX_HOME:-~/.codex}/agents`. Project Codex and Pi share `PROJECT/AGENTS.md`.

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

1. **Ready.** Reject cycles across hard and read-only edges. Confirm clean,
   isolated checkouts, disjoint ownership, and current `PASS` verdicts for
   hard prerequisites. Serialize overlapping readers and writers by default.
   A speculative reader needs a named frozen, verified ref and re-verification
   after the writer's new `PASS`.
2. **Invalidate.** Bind each verdict to `REF`, `BASE`, and `VERIFIED_AGAINST`.
   Before landing, check the branch, `HEAD`, and clean status including
   untracked files. The base and hard input refs must still match.
   - For a `READS`-only edge, use `git diff --name-status -z -M -C <old>..<new>`
     from the last checked upstream ref (merge-base on the first comparison).
     Parse both paths for renames and copies and the old path for deletions.
     Keep the existing verdict only when no path intersects its `READS`.
   - Treat stale verdicts as unverified. Have Vera re-verify in a clean trial
     checkout combining the stream and intended inputs. Rerun Felix only
     when edits are needed. An unchanged consumer `REF` does not invalidate
     its own dependents by itself.
   - More than three invalidations from one change calls for one contract or
     integration check, or a pause for confirmation. Required evidence still
     applies.
3. **Join.** Bind the separate combined check to the clean integration
   `INTEGRATION_REF`, target `BASE`, and all landed `INPUT_REFS`. Check those
   bindings again before final merge. If they move, the join is stale. Route
   join fixes to an owning Felix or assign narrowly scoped integration work.

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

The live Q0/Q1 comparison is pending. Run the offline self-test or inspect the
options without invoking a provider.

```sh
python3 tests/live-graph.py --self-test
python3 tests/live-graph.py --help
```

### Benchmark configuration

- `Q0` is pinned to the original v1 commit
  `6715d8d52a1d69480be2f2bec778184fb7abd3cf`. Pass clean source checkouts
  with `--q0` and `--q1`, and pin `Q1` with `--q1-sha <40-char-sha>`.
  The runner's Q1 install uses the v2 default from this checkout.
- By default the Q1 commit must be a strict descendant of Q0. To use a sibling
  checkout, such as the [archived v1 tip][v1-tip], pass `--allow-diverged-q0`.
  The driver records `merge_base` in the revision metadata.
- Live runs use Claude Code, matching model and permissions, and `--no-web`.
  Run at least five trials per scenario per variant. `--budget` sets the
  per-invocation budget. S5 allows up to three invocations and S3 and S5b
  allow two. Keep raw JSONL, fixture repos, snapshots, and results in an
  `--out` directory outside the runner and both source checkouts.

[v1-tip]: https://github.com/LazyGreed/quintet/tree/460f9e9c4ce2d057d9fb72365489fe9a132c03af

### Scenario gates

- **S1.** Accepted single-stream fix, zero extra workers, exact static tokens
  at most Q0, median runtime tokens at most 115% of Q0.
- **S2.** No regression in accepted completion or worker count for disjoint
  parallel streams.
- **S3.** Improve clean invalidation by at least two of five trials, or pass
  at least four of five if Q0 passes two or fewer. A tie qualifies when it
  cuts unnecessary consumer calls. Evidence covers the initial API failure,
  passing fix, and final binding.
- **S4.** Reduce ownership violations, targeting zero in at least four of five
  trials. Audit reflog transitions and attributable patches. Exclude imported
  paths from ownership violations.
- **S5.** Zero stale or dirty landings and strictly fewer unsupported completion
  claims. Inspect snapshots before mutation and landing.
- **S5b.** Diagnose a semantic join failure and route it within two rounds using
  refreshed inputs. Pause at the first join to test the exact joined commits.

Across S1 through S5, unsupported completion, ownership violations, and
unnecessary invocations must stay at or below Q0. Reflogs can miss uncommitted
writes or rewritten history. The driver records observations about provenance
and checkout cleanliness at landing. Full release evaluation still needs exact
rendered token counts, nested and reused call attribution, and trace review.
Report per-run evidence and medians. Mark unknown metrics and missing
checkpoints separately from passing gates. The optional overlap helper and
experiment branches remain deferred. Retain a later helper only if S4 or S5b
shows it detects collisions or avoids rework that Q1 misses.

## Harness notes

- Pi requires Pi 1.1.0 or later. The installer registers
  `npm:@tintinweb/pi-subagents` and `npm:pi-web-access` when they are absent,
  and writes `subagents.json` with `"defaultJoinMode": "group"`. That setting
  batches completion notices and delays early results. Inspect workers in
  FleetView or `/agents`. Worker profiles use `prompt_mode: append`.
- Use native peer messaging only when the host exposes it. Otherwise relay
  through the coordinator. [Peer messaging by harness](peer-messaging.md)
- Background work may stop when the parent session exits. Check native state
  on resume. Push, final target merges, production deployment, irreversible
  cleanup, and credential or permission changes need explicit approval.
  [Shared coordinator contract](../AGENTS.md)
