# Model and effort guide

Quintet uses the models and providers configured in your harness. Both
workflows install the same profiles and leave those settings in place.
Choose models and thinking effort based on the work each role needs to do.

| Role | Capability | Suggested effort |
| --- | --- | --- |
| Coordinator | Planning, delegation, and judgment | High |
| Nora | Research and codebase tracing | Medium to high |
| Felix | Implementation and focused checks | High |
| Vera | Independent review | High |
| Iris | Tool use and acceptance checks | Medium |

- In Pi, configure per-agent model and thinking overrides through
  `@tintinweb/pi-subagents`.
- In Claude Code, a subagent can inherit the session model or use a dedicated
  model.

Use lighter settings for routine tasks and stronger reasoning for risky
changes. Consider a different model family for Vera when independent review
would benefit from it.
