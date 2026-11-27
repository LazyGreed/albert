# Peer messaging

Workers can send focused handoffs when the active harness exposes a native
peer transport. The coordinator assigns work and enforces approval boundaries
in both workflows. In v1 it sequences named handoffs and runs the combined
check. In v2 it also determines when evidence is stale, assigns re-verification,
and owns the revision-bound join.

## Transports

| Harness | Transport | Routing |
| --- | --- | --- |
| Antigravity CLI `/swarm` | Peer tools in an active swarm | Use when exposed |
| Antigravity subagents | Coordinator tools | Coordinator relay |
| Claude Code agent teams | `SendMessage` in an active team | Use when exposed |
| Claude Code subagents | Version-dependent | Relay if tools are absent |
| Pi | Coordinator steering or exposed peer tools | Check active tools |
| Oh My Pi | `agent://` where supported | Check the active route |

The installer does not start a swarm or agent team. In Pi with
`@tintinweb/pi-subagents`, the `Agent` tool confirms dispatch capability.
Check for peer transport separately. Oh My Pi is a compatibility reference
without a dedicated installer target.

## Handoffs

Use direct messages for API contracts, blockers, dependency changes, and
review findings. Include the stream, path or ref, verified fact, and next
action.

```text
STREAM: api
TO: felix-ui
PATH/REF: server/validation.ts
FACT: Errors use the `code` field
ACTION: Update mapping within assigned paths
```

Notify the coordinator when a message changes ownership, scope, acceptance,
risk, or a decision. Workers need the coordinator to reassign ownership or
act on approval boundaries. Only the assigned Vera issues the independent
verdict for the stream. Relay through native completion and steering if
direct transport is unavailable.

For a peer-messaging trial, compare serial execution, coordinator relay, and
direct handoffs on accepted work, integration defects, tokens, and user
interventions.

[Workflow](workflow.md) ·
[Claude Code teams](https://code.claude.com/docs/en/agent-teams) ·
[Claude Code subagents](https://code.claude.com/docs/en/sub-agents) ·
[Pi subagents](https://github.com/tintinweb/pi-subagents)
