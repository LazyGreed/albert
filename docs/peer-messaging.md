# Peer messaging

Quintet uses native peer messaging when the host harness supports it. **The coordinator retains ownership and approval authority.**

## Supported transports by harness

| Harness | Supported mechanism | Default routing |
| --- | --- | --- |
| Antigravity CLI `/swarm` | Peer messages inside an active swarm | Use native messaging if enabled |
| Antigravity ordinary subagents | Coordinator-to-worker tools; peer access differs | Relay through coordinator |
| Claude Code agent teams | `SendMessage` when teams are enabled | Narrow direct handoffs |
| Claude Code ordinary subagents | Version-dependent | Relay through coordinator |
| Pi with `@tintinweb/pi-subagents` | Coordinator steering; peer transport experimental (2026-11-21) | Relay through coordinator |
| Oh My Pi | `agent://` in supported configurations | Check active route |

> [!IMPORTANT]
> Installing Quintet does not start an Antigravity swarm or Claude agent team automatically. Before using peer messaging, verify active runtime tools: Antigravity needs an active `/swarm` with peer tools, Claude needs agent teams/`SendMessage`, Pi's `Agent` tool alone does not imply peer messaging, and OMP requires a valid `agent://` route.

## Message format and boundaries

Messages may carry only a verified dependency, API contract, blocker, or review finding:

```text
STREAM: api
TO: felix-ui
PATH/REF: server/validation.ts
FACT: Error field is code, not errorCode
ACTION: Update mapping within assigned paths
```

Peers cannot reassign file ownership, spawn workers, change acceptance, or approve actions; relay any scope or permission changes to the coordinator. Use native completion and steering whenever direct routing is unavailable. No extra message broker or polling service is used.

Measure any peer-messaging benefit against serial execution and coordinator-relay parallel runs across accepted work, integration defects, tokens, and interventions.

**References:** [workflow](workflow.md), [Claude teams](https://code.claude.com/docs/en/agent-teams), [Claude subagents](https://code.claude.com/docs/en/sub-agents), [Pi subagents](https://github.com/tintinweb/pi-subagents).
