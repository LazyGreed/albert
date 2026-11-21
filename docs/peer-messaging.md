# Peer messaging by harness (research snapshot: 2026-11-21)

Albert uses native agent execution. Messaging transports are optional; none may override Albert's task ownership, safety, approval, or verification policy. Test the installed harness version before claiming a channel is available.

| Harness | Mechanism | Peer-to-peer? | Safe Albert behavior |
| --- | --- | --- | --- |
| Antigravity CLI `/swarm` | Native board/mentions, worker roster and direct coordinator tools | Yes inside an active swarm, when enabled | Let workers exchange narrow contracts/blockers; Albert remains ownership authority. Merely installing Albert as an Antigravity plugin does **not** automatically start `/swarm` or guarantee swarm messaging. |
| Antigravity CLI ordinary subagents | `invoke_subagent`, `send_message`, `manage_subagents` on coordinator | Coordinator-to-worker established; direct peer permissions must be checked | Relay through Albert unless current worker exposes documented peer routing. |
| Claude Code agent teams | Native team task list and `SendMessage` between teammates | Yes when agent teams enabled and available | Use direct issue/contract handoffs, copy coordinator for changes in owned paths or scope. |
| Claude Code ordinary subagents | Parent dispatch/result; some versions expose named subagent messaging | Version/config-dependent; not equivalent to teams | Prefer coordinator relay unless direct peer capability is observed. |
| Pi with `@tintinweb/pi-subagents` | `Agent`, `steer_subagent`, `get_subagent_result`, named instance aliases | Parent control is documented; peer feature experimental as of this snapshot | Use Albert relay; do not install an experimental extension or assume a peer tool exists. |
| Oh My Pi (OMP) | Native `agent://` communication features | Available in documented supported OMP configurations | Allow targeted native messages with an owner/contract acknowledgment; fall back to Albert if tool unavailable. |

## Handshake

1. A workstream has a stable ID, named instance, checkout, *exclusive* write allowlist, explicit forbidden/shared paths, acceptance criteria, and verifier.
2. Only messages about an interface contract, verified dependency, blocker, or review finding may cross streams. Include `STREAM`, `TO`, `PATH/REF`, `FACT`, and `ACTION`.
3. Receiving a message does **not** change ownership, authorize another write, or satisfy acceptance. Albert explicitly reassigns any ownership/acceptance change and records the integration impact in the active task context.
4. If native peer routing is not available, workers report to Albert. Albert steers the existing target instance or passes a new workstream brief; do not spawn duplicate workers just to send a message.
5. Keep messages short and source-anchored; pass pointers, not entire transcripts or credentials. No custom polling loops or new message broker.

## Harness checks before enabling peer handoffs

- **AGY:** check active mode (`/swarm` versus ordinary subagents), native permission/tool availability and the installed CLI help. Swarm peer board must not be inferred from an Albert plugin profile alone.
- **Claude:** check whether experimental agent teams are enabled, and whether the current subagent/team environment actually exposes `SendMessage` and peer names. Ordinary subagent sessions need not share the same transport.
- **Pi:** inspect extension version and native tools at runtime. `Agent` + `steer_subagent` means Albert can coordinate, not necessarily that worker A can message worker B.
- **OMP:** inspect active `agent://` route and target identifiers; avoid treating an external pi-subagents feature as bundled into OMP.

## Evaluation

Compare identical, isolated multi-module tasks with (A) serial Felix, (B) parallel Felix + Albert relay, (C) parallel Felix + native peer messages when supported. Track accepted workstreams, integration failures, cross-owner edits, total tokens, wall time, escalations, missed blockers, and interventions. Do not assume peer messaging is faster without measurements.

## References

- [Albert coordinator policy](../AGENTS.md)
- [Albert workflow](workflow.md)
- [Claude Code agent teams documentation](https://code.claude.com/docs/en/agent-teams)
- [Claude Code subagents documentation](https://code.claude.com/docs/en/sub-agents)
- [Pi subagents](https://github.com/tintinweb/pi-subagents)
- [Pi subagents experimental peer messaging PR](https://github.com/tintinweb/pi-subagents/pull/421)
- [Oh My Pi](https://github.com/can1357/oh-my-pi)
