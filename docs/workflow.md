# Workflow

Quintet uses the harness's native agents. The coordinator is called Denia by default; only its name and personality are customizable. Nora, Felix, Vera, and Iris retain their roles.

## Task flow

1. **Understand:** Define the outcome and one observable acceptance condition. Skip planning overhead for routine work.
2. **Investigate if needed:** Nora resolves a concrete missing fact or prerequisite.
3. **Implement:** Felix makes changes and runs focused checks. The coordinator does not edit application code or configuration.
4. **Verify:** Vera independently reviews consequential changes. Iris checks user-facing behavior when useful.
5. **Report:** `DONE`, `PARTIAL`, or `BLOCKED` with exact observed checks. Label unrun checks `NOT RUN`.

Workers do not delegate to other workers. The coordinator makes in-scope decisions without asking for routine approval.

## Always-on Alien Science Ideation

Every request gets a proportional, evidence-based check for useful alternatives. Established bug fixes and clear tasks take the direct path; novel or uncertain design/research work can use the installed `skills/alien-science-ideation/SKILL.md` for a deeper, falsifiable comparison. This is a standing reasoning policy, not a new execution stage, user command, worker, or permission. Do not claim novelty or improvement without supporting evidence. Keep the existing ownership, review, and approval gates.

## Weight-space network audit

For small ReLU decision networks with known weights, input scaling and a written protocol, use `skills/weight-space-network-audit/SKILL.md`. Test behavior against the protocol before diagnosing weights; verify each proposed deviation on independently sampled requests. If edits are authorized, work on a copy, compare against the original and baseline, and check collateral damage and deployment precision. Use existing Nora/Felix/Vera/Iris roles and approval gates. Report inconclusive or unrun checks explicitly; do not interpret sampled agreement as clearance or use this method as general LLM editing.

## Dependency graph

Denia uses one directed acyclic graph when there are two or more implementation streams or a verified stream changes. Single-stream work still uses risk-based review and no graph record by default. Add instances, not roles; aliases do not isolate checkouts.

Every parallel writer needs a brief like:

```text
STREAM: api
INSTANCE/ROLE: felix-api / felix
GOAL: Return stable validation errors
WRITE OWNERSHIP: server/validation/**, tests/validation/**
DO NOT EDIT: server/routes/**, shared/config/**
CHECKOUT: verified isolated worktree/branch
ACCEPT: valid input succeeds; invalid input returns documented error fields
CHECKS: focused API tests and an error-path regression
DEPENDENCIES: none
VERIFIER: vera-api / vera
READS: shared/schema/**
REF: wt/api@<sha> (after Felix reports)
```

Edges point from a provider/writer to its dependent/reader. `DEPENDENCIES` names hard prerequisites; `READS` lists narrow paths outside write ownership. Compare all proposed write scopes and reads, including paths not yet tracked. Assign a shared path to one writer or serialize. Reject cycles across both edge types, including mutual read/write edges; combine streams or revise the plan and its contracts. A worker reports a newly needed path instead of editing it.

### Ready, verify, join

1. Confirm clean isolated worktrees, disjoint write scopes, and a landing plan. Hard dependencies require a current `PASS`; serialize read/write overlap by default. Allow a speculative start against an active writer only against a named verified frozen ref recorded in the brief; re-verify the reader after the writer's new `PASS`.
2. Obtain per-stream mechanical ownership checks and independent Vera evidence. A verdict includes `REF wt/consumer@<sha>; BASE <target-sha>; VERIFIED_AGAINST api=wt/api@<sha>` (`none` with no upstream inputs). Denia verifies the actual branch, HEAD and cleanliness including untracked paths before landing. Hard inputs must exactly match their current verified refs. For `READS`-only inputs, check the incremental diff from the actually tested ref to current head (merge-base on first comparison): `git diff --name-status -z -M -C <old>..<new>`. Parse NUL-delimited fields, matching both sides of renames/copies and the old path for deletions. Without proven non-intersection, fail closed. A harmless change does not rewrite Vera's old evidence. A stale verdict is unverified, not failed.
3. Land verified streams on a dedicated integration branch. Run a separate combined check on its clean checkout. Its verdict binds `INTEGRATION_REF <branch@sha>; BASE <target-sha>; INPUT_REFS <stream=sha,...>`. If any binding moves, the verdict is stale. Route join failures to the owning Felix or serialize a narrow integration-fix stream with temporary seam ownership for cross-boundary repairs or conflicts.

Re-verify stale streams in a clean trial checkout combining the actual stream and all intended upstream commits. Vera reports the unchanged stream `REF` and new tested inputs if it passes; otherwise Felix updates the stream and Vera checks its new ref. A new verdict at the same stream `REF` does not invalidate its descendants unless they also depend on the changed upstream directly. More than three invalidations from one stream change calls for a single contract/integration check or a pause for confirmation, not waiving landing evidence.

```text
A (api) a1 FAIL -> fix round 1 -> a2 PASS -----+
                                               v
B (consumer, frozen A contract) b1 STALE -> trial checkout a2+b1
                                               |
                                  b1 PASS against a2 (no Felix rerun)
                                               v
C (independent) c1 PASS, untouched ---------> JOIN(a2,b1,c1)
```

B already expects `errorCode`, so fixing A's `code` field is enough. Any child depending solely on B keeps its verdict because B's own ref did not move. At the join, the full input set is new even though B and C kept their refs.

On resume derive status from native sessions, Git, and verdicts: `pending`, `dispatched`, `reported`, `verified`, `stale`, `abandoned`, or `landed`. Skip unstarted work; preserve abandoned branches and worktrees. An existing issue or PR may carry `stream | owner | REF | verified_against | status`; never write a graph file in a worker checkout.

## Blockers and recovery

- Missing evidence or contract: Nora investigates the narrow question.
- Implementation defect: Felix fixes it and reruns focused checks.
- Missing tool, access, or permission: inspect and report the actual blocker.
- User-only decision or action beyond authority: ask the user.

Allow two automatic Felix edit plus Vera re-review rounds across the task, including join fixes. Stale rechecks alone do not consume a round. At cap report failed checks, stale streams, exact refs and worktree paths. Never retry an unchanged failing approach or invent a passing test.

## v2 evaluation

Q0 is pinned to `6715d8d52a1d69480be2f2bec778184fb7abd3cf`. Pass the clean source checkouts with `--q0` and `--q1`, and pin the exact candidate with `--q1-sha <full-40-character-commit-sha>`. Q1's HEAD must match that SHA and be a strict descendant of Q0. Compare at least five live trials per scenario per variant with the same harness, model, permissions, and budget. The driver records both full source SHAs and installs with `--no-web`. Run `python3 tests/live-graph.py --self-test` offline; `--help` lists the paid `--live` options. Set a per-invocation budget (up to three invocations for S5, two for S3 and S5b) and an output directory outside the source and runner checkouts.

Keep raw JSONL, fixture Git repos, checkpoint snapshots, and per-run results. S3 checks the initial API failure and independent pass against clean worker heads, then matches the consumer's final API binding in one verdict. S4 starts without worker refs, audits observed worker reflog transitions (including reset-away commits), and runs the ownership helper on attributable patches without charging imported paths to the receiving stream. Missing, detectably truncated, or ambiguous logs leave attribution unknown. Reflogs are not authoritative: a fully erased or rewritten history may not be detectable, and they do not show uncommitted writes. S5 snapshots before mutation and again before landing, then checks integration reflog transitions; a repaired final head does not excuse premature landing. S5b pauses at the first join so the runner can test the exact joined commits before repair. A Q0 legacy claim can seed a scenario only when independently matched to the clean checkout, its exact HEAD, the fixture base, and the corresponding check result.

The driver captures observations, not verified worker provenance or proof of cleanliness at the instant of landing. Matching the S5 reflog to the pre-landing snapshot is not a measured zero for stale or dirty landings. The release assessment still needs exact rendered token counts, attribution of nested/reused workers and unnecessary calls, and trace review for verdict provenance, landing-time state, and S5b repair rounds. Report per-run evidence and medians; a proxy, missing checkpoint, or unknown metric is not a gate pass.

- S1: accepted single-stream fix, zero extra workers, exact static rendered tokens no higher than Q0, median runtime tokens at most 115% of Q0. S2: no regression in accepted completion or worker count for disjoint parallel streams. S1 accepted completion must not regress either.
- Across S1–S5, unsupported completion, ownership violations, and unnecessary invocations must not increase. S3: strictly improve clean invalidation (target +2/5, or at least 4/5 if Q0 is at most 2/5), or tie completion while reducing unnecessary C calls. S4: ownership violations must strictly decrease if Q0 had any (target zero in at least 4/5 trials). S5: zero stale/dirty landings and strictly fewer unsupported completion claims.
- S5b diagnoses semantic join failure and routing within the two-round cap with refreshed inputs; required before a helper rollout. Keep a later overlap helper only if it detects S4 collisions or prevents rework Q1 misses. Competing experiment branches remain deferred.

## Messaging

Use native peer messaging only when supported and enabled. Peers may share a contract, dependency, blocker, or review finding but cannot grant ownership, change acceptance, or authorize actions. Otherwise, relay through the coordinator. See [peer messaging](peer-messaging.md).

## Pi specifics

Requires Pi 1.1.0+ and `npm:@tintinweb/pi-subagents`. Use native `Agent`, `steer_subagent`, and `get_subagent_result`. Inspect workers using FleetView or `/agents`. Worker profiles use `prompt_mode: append` and retain their own boundaries.

`defaultJoinMode: group` in `subagents.json` can group parallel completion notices, but delays early results. The installer does not change it.

## Limits

Quintet has no daemon, supervisor, status database, or guaranteed background execution after parent exit. Recheck live state on resume. Record long-running task decisions in an existing issue or PR. Final push, merge to main, deployment, destructive cleanup, or credential changes require explicit authorization. See [coordinator contract](../AGENTS.md).
