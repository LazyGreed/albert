# Model and effort guide

Quintet leaves your harness's model and provider configuration untouched. Pick models and thinking effort directly in your harness.

| Role | Best-fit capability | Recommended effort |
| --- | --- | --- |
| **Main agent** (Denia by default) | Planning, delegation, judgment | High |
| **Nora** | Research, codebase tracing | Medium / high |
| **Felix** | Implementation and focused checks | High |
| **Vera** | Independent review (ideally a different model family) | High |
| **Iris** | Tool use and acceptance checks | Medium |

- **Pi:** Configure per-agent model and thinking overrides via `@tintinweb/pi-subagents`.
- **Claude Code:** Subagents can inherit the session model or pin a dedicated one.
- **General tip:** Avoid hardcoded model IDs that age out quickly; use lighter settings for routine work and stronger reasoning for risky changes.
