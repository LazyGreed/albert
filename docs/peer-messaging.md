# Peer messaging

Quintet uses native peer messaging when available. **Denia is the hub.** Peer messages can report a changed `REF`, `READS` contract, or dependency, but do not advance graph state. Denia checks the current input closure, assigns re-verification, and owns the separate join gate and approval boundaries. A peer can share trial-check evidence; only the assigned Vera issues the bound verdict.

| Harness | Supported mechanism | Default |
| --- | --- | --- |
| Antigravity CLI `/swarm` | Peer messages inside an active swarm | Use native messaging if enabled |
| Antigravity ordinary subagents | Coordinator-to-worker tools; peer access differs | Relay through coordinator |
| Claude Code agent teams | `SendMessage` when teams are enabled | Narrow direct handoffs |
| Claude Code ordinary subagents | Version-dependent | Relay through coordinator |
| Pi with `@tintinweb/pi-subagents` | Coordinator steering; peer transport experimental (2026-11-21) | Relay through coordinator |
| Oh My Pi | `agent://` in supported configurations | Check active route |

Installing Quintet does not automatically start an Antigravity swarm or Claude agent team. Check actual runtime tools.

Messages may share only a verified dependency, API contract, blocker, or review finding:

```text
STREAM: api
TO: felix-ui
PATH/REF: server/validation.ts
FACT: Error field is code, not errorCode
ACTION: Update mapping within assigned paths
```

Peers cannot reassign file ownership, spawn workers, change acceptance, or approve actions. Relay scope or permission changes to the coordinator. Use native completion and steering if direct routing is unavailable. No extra message broker or polling service.

**Check before use:** Antigravity must have an active `/swarm` and peer tools; Claude must expose agent teams/`SendMessage`; Pi's `Agent` tool alone does not imply peer messaging; OMP needs a valid `agent://` route.

Measure any benefit against serial execution and coordinator-relay parallel tasks, including accepted work, integration defects, tokens, and interventions.

References: [workflow](workflow.md), [Claude teams](https://code.claude.com/docs/en/agent-teams), [Claude subagents](https://code.claude.com/docs/en/sub-agents), [Pi subagents](https://github.com/tintinweb/pi-subagents).
