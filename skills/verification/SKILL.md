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
- `scripts/check-ownership.sh --worktree` unions `git diff --name-only --no-renames -z <base>`, `git diff --cached --name-only --no-renames -z <base>`, and `git ls-files --others --exclude-standard -z`. That set includes a staged edit whose worktree matches the base, a staged add removed from the worktree, an unstaged edit, an untracked non-ignored file, and both paths of a rename. `--head` stays a committed diff.
- `scripts/check-graph.sh ready "$spec"` checks graph cycles and ownership overlaps. Spec records are blank-line-separated and use `id`, `write`, `read`, `depends`, `status`, `ref`, `worktree`, and `verified_against`. Repeat the edge or path keys for multiple values. A hard dependency needs `PASS` and a clean worktree at its `branch@sha` ref. SHA abbreviations must resolve unambiguously and contain at least seven hex digits.
- Use the bare target commit SHA for `BASE` in `STREAM` and `JOIN` verdicts. For `--base-ref` only, set `base_ref="${target_branch}@${BASE}"`.
- `scripts/check-graph.sh invalidate --base-ref "$base_ref" "$spec"` checks the current base and each clean stream worktree against its ref. For every `depends` entry require `PASS` and matching `verified_against` evidence (`id@sha`). For read-only evidence use `git diff --name-status -z -M -C` and check both paths of renames and copies against `read` patterns. A missing old commit or an intersection makes that evidence stale.
- `scripts/check-graph.sh join --base-ref "$base_ref" --integration-ref "$INTEGRATION_REF" --integration-worktree "$integration_worktree" "$spec"` checks the clean integration worktree and each clean `PASS` input against their refs. The base and all input commits must be ancestors of integration HEAD.
- For `invalidate` and `join`, the SHA in `base_ref` must match the named local branch tip in the worktrees' common Git repository. `--repo <dir>` can select that repository explicitly. The checker clears Git repository-routing environment overrides and disables replacement objects and grafts. It uses the supplied worktree paths and their repository configuration.
- For read-only specialists (Nora, Vera, Iris), verify checkout integrity mechanically with `scripts/check-readonly.sh`: take `snapshot [repo-dir]` into a temporary snapshot file before running checks and run `verify <snapshot-file> [repo-dir]` afterward (`READONLY_OK` on unchanged state, `READONLY_VIOLATION` on any HEAD, tracked, or untracked change).
- Report exact commands and outcomes. Mark missing checks `NOT RUN` or `BLOCKED`; state unverified acceptance conditions and material risks.
- Stop after bounded, relevant retries. Do not weaken tests or expand scope merely to produce a green result.
