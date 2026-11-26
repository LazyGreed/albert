# Quintet v2 (graph-engineering edition)

**One voice. Four specialists. Your rules.**

Quintet coordinates coding tasks inside Pi, Claude Code, and Antigravity CLI using native subagents, without an extra daemon, runtime, or database. Customize the main agent's name and style in `PERSONALITY.md`; the four specialists keep their fixed roles.

## Agents

| Agent | Responsibility | Scope |
| --- | --- | --- |
| **Main agent** (Denia by default) | Delegate, coordinate, verify, report | Main session only |
| **Nora** | Research, investigate, trace root causes | Read-only |
| **Felix** | Implement changes and run focused checks | Exclusive owned paths |
| **Vera** | Independently review diffs and check evidence | Read-only |
| **Iris** | Test user-facing acceptance and smoke behavior | Read-only on app code |

Denia uses a dependency graph for multi-stream work with exclusive file ownership, revision-bound reviews (`REF` / `BASE` / `VERIFIED_AGAINST`), and a separate integration check. Routine single-stream work still uses risk-based review. The [`v1` branch](https://github.com/LazyGreed/quintet/tree/refs/heads/v1) carries the coordinator-centric edition.

> [!NOTE]
> The [live Q0/Q1 comparison](docs/workflow.md#v2-evaluation) has not been run yet. Deterministic CI checks and the offline graph benchmark self-test pass locally.

## Specialized skills

- **Alien Science Ideation (opt-in):** Installed by default, loaded only when the user explicitly asks for alien science, alien ideation, cognitively unavailable research directions, or the skill by name. Ordinary research, brainstorming, or unconventional tasks do not activate it. See [Alien Science Ideation](skills/alien-science-ideation/SKILL.md).
- **Weight-space network audit:** Installed by default under the [coordinator contract](AGENTS.md#task-specific-weight-space-network-audit) with three activation modes:

| Request type | Mode | Scope |
| --- | --- | --- |
| Small ReLU decision network repair or audit | `references/relu-audit.md` | Default specialized path for accessible weights and an explicit protocol |
| Read-only checkpoint inspection | `AUDIT_ONLY` | Architecture and weight audit only; a weight file alone never authorizes edits |
| Explicit broader-method or model improvement | `AUTO_IMPROVE`, `DIRECT_ONLY`, or `RESEARCH` | Cross-architecture diagnosis and reversible edits on safe copies; never unrequested LLM editing, full training, or original-checkpoint mutation |

See [weight-space network audit](skills/weight-space-network-audit/SKILL.md) for full details.

## Install

```sh
git clone --branch v2 https://github.com/LazyGreed/quintet.git
cd quintet
```

Run `./install.sh` for the interactive Pi, Claude Code, and Antigravity CLI installer, or pass flags directly:

```sh
# Pi: requires Pi 1.1.0+ and the subagents package
pi install npm:@tintinweb/pi-subagents
./install.sh --harness pi --scope global

# Claude Code
./install.sh --harness claude --scope global

# Antigravity CLI
./install.sh --harness antigravity --scope global
```

For a single repository, pass `--scope project --target /path/to/project`. Add `--dry-run` to preview changes without writing files. The installer backs up files it replaces, preserves existing model/provider settings, and does not copy bundled harness settings. Pi web access registers `pi-web-access` when enabled.

> [!WARNING]
> **Updating an older checkout?** Before pulling or switching revisions, save independent copies of any user configs symlinked into this repository, then point your harness at those copies. Legacy `settings.json`, `claude-settings.json`, `antigravity-settings.json`, and bundled `pi-blackhole` configs were removed from this repository; the installer does not rewrite external symlinks or remove user-managed Blackhole installs.

## Customize the main agent

Edit `PERSONALITY.md` beside `AGENTS.md` to change the main agent's name and communication style:

```md
Name: Kanade

# Personality

- Be concise and direct.
- Explain important choices, not routine steps.
```

Rerun your install command to apply changes. Global installs read `PERSONALITY.md` directly across Pi, Claude Code, and Antigravity (including the coordinator agent and plugin display name). Project installs create `PROJECT/PERSONALITY.md` beside `PROJECT/AGENTS.md` if missing and never overwrite it on reinstall.

Only the main agent uses `PERSONALITY.md`. Nora, Felix, Vera, and Iris keep their fixed roles, permissions, approval gates, and verification standards.

### Antigravity naming and legacy migration

- **Plugin identity:** Antigravity installs register the coordinator agent as `quintet` in both scopes (`~/.gemini/config/plugins/quintet` globally; `PROJECT/.agents` per project).
- **Legacy `plugins/albert` migration:** Global Antigravity installs replace an older `plugins/albert` directory only after the new `plugins/quintet` tree is complete.
- **Preserved user content:** Text outside `<!-- ALBERT MANAGED START -->` / `<!-- ALBERT MANAGED END -->` in `rules/AGENTS.md` is carried into the new `rules/AGENTS.md` before removal. Any unrecognized file, directory, or symlink inside `plugins/albert` keeps the old directory in place, lists those entries, and prints the exact `rm -rf` command.
- **Generated files:** Re-installing overwrites generated agent and skill files in place; use `--dry-run` to preview carry-over and migration output safely.

## Workflow

1. Describe the outcome.
2. Denia delegates the smallest necessary work.
3. Felix implements; Vera independently reviews consequential changes; Iris checks user-facing behavior when useful.
4. Denia reports verified results, gaps, and required approvals.

Parallel writers require isolated worktrees and exclusive write scopes. Each stream needs a mechanical ownership check (`check-ownership.sh`) and an independent Vera `PASS` before landing on the integration branch, followed by a separate combined check. Read-only specialists can verify checkout integrity mechanically with `check-readonly.sh`. Pushing, merging to the target branch, production deployment, and irreversible cleanup require explicit authorization.

## Options and checks

| Option | Purpose |
| --- | --- |
| `--harness pi,claude,antigravity` | Install one harness or a comma-separated subset |
| `--scope global \| project --target PATH` | Install globally or into one target repository |
| `--with-web` / `--no-web` | Include or skip installer-managed web tools and Pi web package registration (`--with-web` by default; `--no-web` never uninstalls packages) |
| `--dry-run` | Preview scripted changes without modifying files |
| `--tui` / `--no-tui` | Force or skip the interactive Pi/Claude Code/Antigravity CLI TUI |

Run the deterministic verification suites locally:

```sh
bash tests/install-e2e.sh
python3 tests/tui-e2e.py
bash tests/workstream-e2e.sh
python3 tests/live-graph.py --self-test
```

These checks cover all three harness installers (with Pi mocked), the interactive TUI, Git worktree ownership and `check-readonly.sh` enforcement, and the offline graph benchmark fixtures. Opt-in live checks are available via `tests/live-parallel-smoke.sh` (Antigravity CLI or Claude Code) and `tests/live-graph.py --live` (Claude Code; see [evaluation protocol](docs/workflow.md#v2-evaluation)).

## Documentation

| Document | Contents |
| --- | --- |
| [Workflow](docs/workflow.md) | Delegation, dependency graph, verification, recovery, and evaluation |
| [Peer messaging](docs/peer-messaging.md) | Native handoffs and coordinator fallback by harness |
| [Model guide](docs/model-guide.md) | Role-level model and thinking effort guidance |
| [Coordinator contract](AGENTS.md) | Authoritative rules enforced in the main session |
| [Agent profiles](agents/) | Fixed specialist definitions (`nora`, `felix`, `vera`, `iris`) |
| [Skills](skills/) | Architecture, domain modeling, documentation, research, verification, Alien Science, weight-space audit |
| [Research lineage and acknowledgements](docs/references.md) | Upstream projects, adapted skills, historical integrations, and papers |

Native background tasks are not guaranteed to survive the parent session exiting.
