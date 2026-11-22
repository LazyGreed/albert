# Model and effort guide

Quintet does not change model settings. Pick models and thinking effort in your harness.

| Role | Useful capability | Effort |
| --- | --- | --- |
| Main agent (Denia by default) | Planning, delegation, judgment | High |
| Nora | Research, reading | Medium/high |
| Felix | Coding and focused checks | High |
| Vera | Independent review, ideally a different model family | High |
| Iris | Tool use and acceptance checks | Medium |

Pi supports agent-level model/thinking overrides via `@tintinweb/pi-subagents`. Claude Code agents may inherit the current model or specify one. Avoid hardcoded model IDs that become outdated. Choose cheaper settings for routine work, stronger reasoning for risky changes.
