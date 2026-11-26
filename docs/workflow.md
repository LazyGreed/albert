# Workflow

Quintet uses the harness's native agents. The coordinator is called Denia by default; only its name and personality are customizable. Nora, Felix, Vera, and Iris retain their roles.

## Task flow

1. **Understand:** Define the outcome and one observable acceptance condition. Skip planning overhead for routine work.
2. **Investigate if needed:** Nora resolves a concrete missing fact or prerequisite.
3. **Implement:** Felix makes changes and runs focused checks. The coordinator does not edit application code or configuration.
4. **Verify:** Vera independently reviews consequential changes. Iris checks user-facing behavior when useful.
5. **Report:** `DONE`, `PARTIAL`, or `BLOCKED` with exact observed checks. Label unrun checks `NOT RUN`.

Workers do not delegate to other workers. The coordinator makes in-scope decisions without asking for routine approval.

## Opt-in Alien Science Ideation

Do not load or apply `skills/alien-science-ideation/SKILL.md` unless the user explicitly asks for alien science, alien ideation, cognitively unavailable research directions, or this skill by name. Ordinary research, design, brainstorming, "be creative", or an unconventional-looking task is not a request. Workers apply it only when the brief says the user explicitly requested it. No new worker, mode, or permission. Do not claim novelty or improvement without supporting evidence. Keep the existing ownership, review, and approval gates.

## Weight-space network audit

For small ReLU decision networks with known weights, input scaling and a written protocol, use `skills/weight-space-network-audit/SKILL.md`. Test behavior against the protocol before diagnosing weights; verify each proposed deviation on independently sampled requests. If edits are authorized, work on a copy, compare against the original and baseline, and check collateral damage and deployment precision. Use existing Nora/Felix/Vera/Iris roles and approval gates. Report inconclusive or unrun checks explicitly; do not interpret sampled agreement as clearance or use this method as general LLM editing.

## Parallel work

Parallel implementation is optional. Add **instances**, not roles: `felix-api`, `felix-ui`. Aliases do not provide filesystem isolation.

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
DEPENDENCIES: ui consumes those error fields
VERIFIER: vera-api / vera
```

Only one writer owns each path, including generated files and lockfiles. If isolation or ownership cannot be verified, run writers sequentially. A worker discovering a new required path reports it to the coordinator instead of editing it.

Before integration, **each** parallel stream needs a mechanical changed-path ownership check and its own independent Vera `PASS` on the actual diff and acceptance evidence. Integrate verified streams into a dedicated task branch. Run a separate combined integration check. Passing isolated streams does not prove integration works.

## Blockers and recovery

- Missing evidence or contract: Nora investigates the narrow question.
- Implementation defect: Felix fixes it and reruns focused checks.
- Missing tool, access, or permission: inspect and report the actual blocker.
- User-only decision or action beyond authority: ask the user.

Allow at most two automatic fix/re-review rounds. Never retry an unchanged failing approach or invent a passing test.

## Messaging

Use native peer messaging only when supported and enabled. Peers may share a contract, dependency, blocker, or review finding but cannot grant ownership, change acceptance, or authorize actions. Otherwise, relay through the coordinator. See [peer messaging](peer-messaging.md).

## Pi specifics

Requires Pi 1.1.0+ and `npm:@tintinweb/pi-subagents`. Use native `Agent`, `steer_subagent`, and `get_subagent_result`. Inspect workers using FleetView or `/agents`. Worker profiles use `prompt_mode: append` and retain their own boundaries.

`defaultJoinMode: group` in `subagents.json` can group parallel completion notices, but delays early results. The installer does not change it.

## Limits

Quintet has no daemon, supervisor, status database, or guaranteed background execution after parent exit. Recheck live state on resume. Record long-running task decisions in an existing issue or PR. Final push, merge to main, deployment, destructive cleanup, or credential changes require explicit authorization. See [coordinator contract](../AGENTS.md).
