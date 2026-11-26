# Quintet v1 (coordinator-centric edition)

**One voice. Four specialists. Your rules.**

Quintet coordinates coding tasks inside your existing AI coding harness. Customize the main agent's name and personality. Its workers retain their fixed roles:

| Agent | Responsibility |
| --- | --- |
| Main agent (Denia by default) | Delegate, coordinate, verify, report |
| Nora | Research and investigate, read-only |
| Felix | Implement and run focused checks |
| Vera | Independently review, read-only |
| Iris | Test user-facing acceptance, read-only |

Quintet uses native subagents. It can split independent work into parallel streams with exclusive file ownership and separate verification. There is no separate runtime, daemon, or database.

**Alien Science Ideation is installed and opt-in.** It is used only when the user explicitly asks for alien science, alien ideation, cognitively unavailable research directions, or the skill by name. Ordinary research, design, brainstorming, or an unconventional-looking task is not a request. No new worker, model download, or additional service is required. See [Alien Science Ideation](skills/alien-science-ideation/SKILL.md).

[Weight-space network audit](skills/weight-space-network-audit/SKILL.md) is installed by default. Under the [coordinator contract](AGENTS.md#task-specific-weight-space-network-audit), its three-mode activation contract covers: (1) default specialized audits or authorized repairs of small feed-forward ReLU decision networks with accessible weights and an explicit protocol (`references/relu-audit.md`); (2) read-only checkpoint audits (`AUDIT_ONLY`) when inspection is requested without asking for edits (a weight file alone never authorizes edits or `AUTO_IMPROVE`); and (3) explicit universal model improvement (`AUTO_IMPROVE`, `DIRECT_ONLY`, or `RESEARCH`) for broader cross-architecture weight-space diagnosis and reversible edits on a safe copy only when the user explicitly requests model improvement or the universal methodology—never unrequested general LLM weight editing, full-model training, or original-checkpoint mutation.

## Install

```sh
git clone --branch v1 https://github.com/LazyGreed/quintet.git
cd quintet
```

Use `./install.sh` for the interactive Pi, Claude Code, and Antigravity CLI installer, or pick a harness directly:

```sh
# Pi: requires Pi 1.1.0+ and the subagents package
pi install npm:@tintinweb/pi-subagents
./install.sh --harness pi --scope global

# Claude Code
./install.sh --harness claude --scope global

# Antigravity CLI
./install.sh --harness antigravity --scope global
```

For one project, use `--scope project --target /path/to/project`. Add `--dry-run` to preview. The installer backs up files it replaces and does not copy bundled harness settings. Pi web access may add its package registration. Existing model and provider settings stay in place.

**Updating an older checkout?** Before pulling or switching revisions, save independent copies of any user configs symlinked into this repository, then point the harness at those copies. This matters if you linked to the repository's Pi `settings.json`, `claude-settings.json`, `antigravity-settings.json`, or bundled `pi-blackhole` config. Those repository files have been removed. The installer does not rewrite those links or remove user-managed Blackhole installs.

## Customize the main agent

Edit the repository's `PERSONALITY.md`, beside `AGENTS.md`, to change the main agent's name and style. For example:

```md
Name: Kanade

# Personality

- Be concise and direct.
- Explain important choices, not routine steps.
```

Rerun your install command to apply changes. Global installs use this file directly; there is no separate personality config directory.

Project installs create `PROJECT/PERSONALITY.md` beside `PROJECT/AGENTS.md` if it does not exist. Edit that file to override the repository template for the project. Reinstalling never overwrites it.

Only the main agent uses the personality. Nora, Felix, Vera, and Iris remain unchanged. Personality changes style, **not** role, permissions, approvals, or verification.

Native agent identifiers and the Antigravity plugin directory remain `albert` for compatibility. Changing the name updates the main prompt and Antigravity plugin display name, not the underlying agent ID or harness title.

## Workflow

1. Describe the outcome.
2. The coordinator delegates the smallest necessary work.
3. Felix implements; Vera independently reviews meaningful changes; Iris checks observable behavior when useful.
4. The coordinator reports verified results, gaps, and required approvals.

Parallel writers require isolated worktrees, exclusive owned paths, and independent reviews before integration. Pushes, final merges to the target branch, deployments, and destructive changes require approval.

## Options and checks

| Option | Purpose |
| --- | --- |
| `--harness pi,claude,antigravity` | Install all three harnesses; pass one name or a comma-separated subset |
| `--scope project --target PATH` | Install in one project |
| `--with-web` / `--no-web` | Include or skip installer-managed web tools and Pi web package registration (included by default). `--no-web` does not uninstall packages or disable tools across the harness. |
| `--dry-run` | Preview scripted changes |
| `--tui` / `--no-tui` | Force the Pi/Claude Code/Antigravity CLI TUI or run without it |

```sh
bash tests/install-e2e.sh
python3 tests/tui-e2e.py
bash tests/workstream-e2e.sh
```

## Documentation

- [Workflow](docs/workflow.md): delegation, ownership, review, recovery
- [Peer messaging](docs/peer-messaging.md): native handoffs by harness
- [Model guide](docs/model-guide.md): choose model and effort
- [Coordinator contract](AGENTS.md): authoritative rules
- [Agent profiles](agents/): unchanged specialist roles
- [Skills](skills/): architecture, domain modeling, documentation, research, verification, opt-in Alien Science Ideation, weight-space network audit

## References

- [Research lineage and acknowledgements](docs/references.md): upstream projects, adapted skills, historical integrations, and papers

Native background tasks are not guaranteed to survive the parent session exiting.
