---
name: verification
description: Verification-first workflow for bug fixes, user-facing features, and consequential refactors. Use to plan focused acceptance checks, reproduce bugs, and verify critical behavior without bloating scope.
---

# Verification-first workflow

Use this skill when debugging, implementing a user-facing feature, or changing consequential behavior. Keep it proportional to risk; this is not a mandate for exhaustive test plans.

## Before editing

- State the expected observable outcome and how it can be checked.
- Inspect the existing diff, relevant call path, conventions, and tests before proposing new structure.
- Follow the smallest vertical slice that establishes the outcome. Avoid unrelated refactors and broad module inventories.

## Bug fixes

- Capture expected vs actual behavior and attempt the smallest reliable reproduction before editing.
- Identify a likely cause from evidence; separate proven facts from hypotheses.
- Preserve or add a regression check for a repeatable failure. When reproduction is impossible, record what was inspected and what remains uncertain.

## Features and refactors

- Trace entry point → domain/state → persistence or external boundary → visible output, as applicable.
- Verify the primary user path plus one high-value failure/edge case when feasible. For refactors, verify the behavior/contracts that must remain unchanged.
- Prefer focused automated checks, then real E2E/smoke evidence when the outcome is user-visible and the environment allows it.

## Evidence and reporting

- Run the most discriminating check after the last edit. Never infer runtime success from code inspection or a dispatch acknowledgement.
- Before landing a parallel stream, check ownership mechanically (`scripts/check-ownership.sh`) and confirm the independent Vera `PASS` using the `WORKFLOW` in the brief. In `v1`, confirm the verdict covers the actual diff and acceptance evidence. In `v2`, also require a clean tree (including untracked files), branch and HEAD matching `REF`, a current `BASE`, and fresh `VERIFIED_AGAINST` inputs under the hard-dependency and `READS` rules.
- Use `scripts/check-ownership.sh --help` to choose `--head` for a committed diff or `--worktree` for a checkout with staged, unstaged, or untracked changes. Vera requires the observed checker result for each parallel or v2 graph stream.
- The coordinator runs the v2 graph gates. `ready` checks dispatch prerequisites, `invalidate` checks that verdicts still cover current revisions, and `join` checks the refs bound to the separate integration check. See the [workflow graph documentation](../../docs/workflow.md#dependency-graph) for responsibilities and `scripts/check-graph.sh --help` for invocation and spec format.
- The coordinator reserves v2 retries with `scripts/check-recovery.py` before starting recovery work. Run it with `--help` for commands. See the [v2 recovery guide](../../docs/workflow.md#v2-recovery) for the ledger, stable scopes, and resume procedure.
- Report exact commands and outcomes. Mark missing checks `NOT RUN` or `BLOCKED`; state unverified acceptance conditions and material risks.
- Stop after bounded, relevant retries. Do not weaken tests or expand scope merely to produce a green result.

## Read-only verification protocol

- When a worker lacks shell access, the coordinator runs the mechanical gates independently and provides the worktree/ref, exact commands, exit statuses, and output. Vera inspects the actual diff and decides whether that evidence covers the acceptance criteria. If the worker lacks file tools, the coordinator also supplies the revision-bound diff. A check with no observed result is `NOT RUN` or `BLOCKED`.
- For any Codex review check that executes a command, use `scripts/check-readonly.sh run-codex <repo-dir> -- <command> [args ...]`. The native session profile governs the session and may prevent the wrapper from creating private scratch. If that happens or the worker lacks command access, the coordinator uses the same wrapper and hands back the observed evidence. Keep the existing sandbox and approvals. If the coordinator cannot run the wrapper, report the check as `BLOCKED`.
- The coordinator records checkout integrity by saving `scripts/check-readonly.sh snapshot <repo-dir>` outside the checkout before checks and running `verify <snapshot-file> <repo-dir>` afterward. The snapshot compares HEAD commit and ref (or detached state), tracked diffs, and untracked, non-ignored fingerprints. It detects differences between two observations. See the [read-only verification guide](../../docs/read-only-verification.md) for coverage and native boundaries.
