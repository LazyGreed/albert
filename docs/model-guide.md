# Model/effort guidance (manual)

No provider-specific model strings appear in role frontmatter. Model and thinking options change by harness and service; choose them in Pi/Claude settings after installation.

| Agent | Preferred capability | Suggested effort |
| --- | --- | --- |
| Albert | strong reasoning, delegation, prompt discipline | high/max |
| Nora | fast reading/research, adequate reasoning | medium/high |
| Felix | strongest reliable coding model | high |
| Vera | independent strong reviewer; ideally different model family from Felix | high |
| Iris | reliable tool use and precise acceptance evidence | medium/high |

Pi: `@tintinweb/pi-subagents` supports model and `thinking` frontmatter, as well as per-call overrides. Use inexpensive effort for routine investigation/verification and strong reasoning for ambiguous design or consequential review. Do not hard-code model IDs or change user settings at installation.

Claude Code: inspect `/model` and current effort configuration; built-in agents can have a `model` field, but leaving it unset uses the caller's current model. Keep manually selected settings intact.
