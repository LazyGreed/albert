# Albert

**One voice. Four workers. Your repository.**

Albert coordinates coding, debugging, and reviews through your harness's native subagents. Describe the outcome you want; Albert delegates the work and reports what was actually verified.

**Supports Pi, Claude Code, and Antigravity CLI.** No daemon, dashboard, database, tmux, or separate runtime.

## Features

- **One point of contact:** Albert coordinates the workers and produces one consolidated report.
- **Smallest useful workflow:** straightforward changes go to Felix without a compulsory plan or research phase.
- **Evidence-based completion:** passing tests, code review, and E2E acceptance are distinct signals; missing checks are marked `NOT RUN`.

## Quick start

Clone the repository:

```bash
git clone https://github.com/LazyGreed/albert.git
cd albert
```

### Antigravity CLI

Uses Antigravity CLI's native plugin & subagent system:

```bash
./install.sh --harness antigravity --scope global
```

### Pi

Requires **Pi 1.1.0 or later** and the [tintinweb/pi-subagents](https://github.com/tintinweb/pi-subagents) package:

```bash
pi install npm:@tintinweb/pi-subagents
./install.sh --harness pi --scope global
```

### Claude Code

Uses Claude Code's built-in subagents:

```bash
./install.sh --harness claude --scope global
```

To configure harnesses interactively, run `./install.sh` without arguments. Then open your coding agent inside a project and describe a task.

## The crew

| Agent | Responsibility | Boundary |
| --- | --- | --- |
| **Albert** | Understand the goal, delegate, verify, report | Does not implement project changes |
| **Nora** | Investigate uncertainty and missing prerequisites | Read-only |
| **Felix** | Implement and run focused checks | One writer per shared checkout |
| **Vera** | Independently review consequential changes | Read-only |
| **Iris** | Run user-facing smoke and E2E acceptance checks | Never invents a passing result |

Workers do not delegate to other workers. Albert coordinates handoffs and communicates with you.

## How tasks flow

1. **Scope:** Albert identifies an observable acceptance condition.
2. **Check prerequisites when warranted:** uncertain or consequential work gets a lightweight check for missing evidence, contracts, or tool access. Routine work skips this step.
3. **Delegate:** Nora investigates specific unknowns; Felix implements the change.
4. **Verify:** Felix runs focused checks; Vera reviews risky changes; Iris tests user-visible behavior when useful.
5. **Report:** Albert summarizes observed checks, unverified boundaries, and remaining blockers.

When Felix is blocked, Albert distinguishes missing knowledge from an implementation defect. It does not blindly repeat the same approach or assume that switching to a larger model supplies missing evidence. See [Workflow and prerequisite-aware delegation](docs/workflow.md).

## Installation options

| Command | Purpose |
| --- | --- |
| `./install.sh` | Interactive installer |
| `./install.sh --harness pi,claude --scope global` | Install both harness profiles globally |
| `./install.sh --harness claude --scope project --target /path/to/repo` | Install into one repository |
| `./install.sh --harness pi,claude --scope project --dry-run` | Preview changes without writing |
| `./install.sh --harness pi --scope global --with-jev` | Enable optional Pi Jev integration |
| `./install.sh --harness pi,claude --scope project --with-web` | Enable web tools for eligible workers |

The installer preserves existing instructions, updates its managed blocks, and backs up changed files. It does not change model settings. Other harnesses with native subagents may use the same `AGENTS.md`, `agents/*.md`, and `skills/` rules, but the installer currently targets Pi and Claude Code only.

### Web research

Web research is enabled by default for Albert and Nora/Felix/Vera (Iris remains minimal):

- **Antigravity CLI:** uses native `search_web`.
- **Pi:** installs `npm:pi-web-access` if missing and grants worker tool access. Configure provider keys in `~/.pi/agent/web-search.json`; dynamic activation may require `web_enable`.
- **Claude Code:** uses native `WebSearch` and `WebFetch`; no extra MCP server is required.
- **Iris:** receives no additional web tools.

Use `--no-web` during installation if you need an entirely offline profile. External content is untrusted. Do not send secrets or private repository material to external providers. Jev is optional and may send code or diffs to its configured endpoint.

### Models and effort

Choose models and reasoning effort in your harness; Albert does not lock you to a provider or overwrite your selections. See [Model/effort guidance](docs/model-guide.md).

## Setup prompt

If you prefer an agent-guided installation, paste this into your current coding agent:

```text
Set up Albert (https://github.com/LazyGreed/albert) in this environment.
Detect whether I use Pi or Claude Code and check the repository's
installation instructions. Install globally unless I specify otherwise.
Ask only about material choices such as optional web/Jev integration.
Verify the installed agent files and managed AGENTS.md/CLAUDE.md block.
Report exact changes and checks; label anything unverified NOT RUN.
```

## Documentation

- [Workflow](docs/workflow.md): lifecycle, prerequisite-aware delegation, verification, and recovery.
- [Model/effort guidance](docs/model-guide.md): choosing capabilities for each agent.
- [Coordinator rules](AGENTS.md): dispatch, first-principles reasoning, safety, and reporting.
- [Agent profiles](agents/): Nora, Felix, Vera, and Iris.
- [Skills](skills/): architecture, domain modeling, UI/UX, documentation, research, and verification.

## Development and checks

Installer smoke tests are available:

```bash
bash tests/install-e2e.sh
python3 tests/tui-e2e.py
```

These tests exercise installation, not agent task quality. For prerequisite-aware delegation, compare verified task completion, token usage, recovery time, and unnecessary research handoffs against the original workflow.

## Limitations and safety

Albert relies on native harness sessions: background tasks are not guaranteed to survive an exited parent process. Concurrent writers require isolated worktrees. Merging, deploying, releasing, changing credentials, and destructive operations need explicit approval. No additional supervisor or persistent task database is introduced.
