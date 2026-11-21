# Quintet

**One voice. Four specialists. Your rules.**

Quintet coordinates coding tasks inside your existing AI coding harness. Customize the main agent's name and personality. Its workers retain their fixed roles:

| Agent | Responsibility |
| --- | --- |
| Main agent (Albert by default) | Delegate, coordinate, verify, report |
| Nora | Research and investigate, read-only |
| Felix | Implement and run focused checks |
| Vera | Independently review, read-only |
| Iris | Test user-facing acceptance, read-only |

Quintet uses native subagents. It can split independent work into parallel streams with exclusive file ownership and separate verification. There is no separate runtime, daemon, or database.

## Install

```sh
git clone https://github.com/LazyGreed/quintet.git
cd quintet
```

Use `./install.sh` for the interactive Pi and Claude Code installer, or pick a harness directly:

```sh
# Pi: requires Pi 1.1.0+ and the subagents package
pi install npm:@tintinweb/pi-subagents
./install.sh --harness pi --scope global

# Claude Code
./install.sh --harness claude --scope global

# Antigravity CLI
./install.sh --harness antigravity --scope global
```

For one project, add `--scope project --target /path/to/project`. Add `--dry-run` to preview. Installer updates back up changed files and keep existing model settings.

## Customize the main agent

Global installs create `~/.config/quintet/PERSONALITY.md` (or `$XDG_CONFIG_HOME/quintet/PERSONALITY.md`). Edit its first line to change the main agent's name:

```md
Name: Kanade

# Personality

- Be concise and direct.
- Explain important choices, not routine steps.
```

Rerun your install command to apply changes.

For a project-specific override, create `PROJECT/.quintet/PERSONALITY.md`. Resolution order: project override, global file, default template. The installer does not overwrite user personality files. Only the main agent reads the personality; Nora, Felix, Vera, and Iris remain unchanged. Personality changes style, **not** role, permissions, approvals, or verification.

Native agent identifiers and the Antigravity plugin directory remain `albert` for compatibility. Changing the name updates the main prompt and Antigravity plugin display name, not the underlying agent ID or harness title.

## Workflow

1. Describe the outcome.
2. The coordinator delegates the smallest necessary work.
3. Felix implements; Vera independently reviews meaningful changes; Iris checks observable behavior when useful.
4. The coordinator reports verified results, gaps, and required approvals.

Parallel writers require isolated worktrees, exclusive owned paths, and independent reviews before integration. Pushing, merging, deploying, and destructive changes require approval.

## Options and checks

| Option | Purpose |
| --- | --- |
| `--harness pi,claude` | Install both harnesses |
| `--scope project --target PATH` | Install in one project |
| `--with-web` / `--no-web` | Toggle web access (enabled by default) |
| `--with-jev` | Optional semantic tools |
| `--dry-run` | Preview changes |

```sh
bash tests/install-e2e.sh
python3 tests/tui-e2e.py
bash tests/workstream-e2e.sh
```

## References

- [Workflow](docs/workflow.md): delegation, ownership, review, recovery
- [Peer messaging](docs/peer-messaging.md): native handoffs by harness
- [Model guide](docs/model-guide.md): choose model and effort
- [Coordinator contract](AGENTS.md): authoritative rules
- [Agent profiles](agents/): unchanged specialist roles
- [Skills](skills/): architecture, domain modeling, UI/UX, documentation, research, verification

Native background tasks are not guaranteed to survive the parent session exiting.

**Migration:** GitHub must be renamed from `LazyGreed/albert` to `LazyGreed/quintet` after merging. Until then, use the current repository URL to clone.
