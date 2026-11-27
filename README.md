# Quintet

Quintet coordinates coding tasks through native subagents in Pi, Claude Code,
and Antigravity CLI. One installer offers two workflows. Both use the same
coordinator contract, worker profiles, and skills.

## Install

```sh
git clone https://github.com/LazyGreed/quintet.git
cd quintet
```

For Pi, install Pi 1.1.0 or later. When that harness is selected, the installer
runs `pi install npm:@tintinweb/pi-subagents` and
`pi install npm:pi-web-access` if `pi list` does not already show them. It
writes `subagents.json` in `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}`.

Run `./install.sh` in a terminal. Use the arrow keys and Enter or Space to
select your harness, scope, and workflow. Review the choices before installing.
`v2` is selected by default.

For scripts, pass `--workflow v1` or `--workflow v2`. Omitting the flag also
selects `v2`.

```sh
./install.sh --harness pi --scope global --workflow v1
./install.sh --harness claude --scope global --workflow v2
./install.sh --harness antigravity --scope project --target /path/to/project
```

Use the current installer with the same harness and scope to switch workflows.
The installer replaces the managed instructions and preserves the text outside
that block. Restart the harness session to load the updated rules.

| Option | Purpose |
| --- | --- |
| `--harness pi,claude,antigravity` | Install any comma-separated subset |
| `--scope global` | Apply across projects |
| `--scope project --target PATH` | Apply to one project, defaulting to `.` |
| `--with-web` / `--no-web` | Enable (default) or omit web tool grants |
| `--dry-run` | Preview without writing files |
| `--tui` / `--no-tui` | Force or skip the terminal installer |

Project rules take precedence over global workflow rules for the active
harness. The installer backs up files it replaces and preserves model and
provider settings. Selecting Pi installs both runtime packages when they are
absent, including with `--no-web`. `--no-web` omits web tool grants from worker
profiles. It does not skip those package installs or remove an existing
registration.

### Antigravity

Both workflows install the global `quintet` plugin at
`~/.gemini/config/plugins/quintet` or use `PROJECT/.agents` for project installs.
The coordinator loads through `rules/AGENTS.md`. Coordinator rule backups live
outside rule discovery, in `~/.gemini/config/quintet-rule-backups` for global
installs or `PROJECT/.quintet-rule-backups` for project installs. If the
installer reports `KEEP RULE`, inspect the named path and move that backup out
of rule discovery before retrying. Use `--dry-run` to see the planned moves.

## Agents and personality

| Agent | Responsibility | Scope |
| --- | --- | --- |
| **Coordinator** | Delegates, sequences work, and verifies | Main session |
| **Nora** | Researches contracts and root causes | Read-only |
| **Felix** | Implements changes and runs focused checks | Owned paths |
| **Vera** | Independently reviews diffs and evidence | Read-only |
| **Iris** | Runs acceptance and smoke checks | Read-only on source |

Denia is the default coordinator. Edit [PERSONALITY.md](PERSONALITY.md) in the Quintet checkout
for global installs. For project installs, edit `PROJECT/PERSONALITY.md`. The
installer creates it if missing and keeps your edits on reinstall. The first
line must be `Name: Your Name`.
Rerun the installer to apply the name and style to the coordinator, including
its global Antigravity display name. The four workers keep their roles.

Antigravity truncates rules above 24,000 bytes. The default personality fits
with either workflow. A long custom personality can exceed the limit.

## Compare the workflows

```mermaid
flowchart TD
  A["Shared: define acceptance and assign roles"] --> B{"Task path"}
  B -->|"Routine single stream"| S["Felix implements, review by risk"]
  B -->|"v1"| V1["Denia sequences named dependency handoffs"]
  V1 --> D1["Ownership check and independent Vera diff verdict"]
  D1 --> I1["Land verified streams and run a separate combined check"]
  B -->|"v2"| V2["DAG: check ownership, inputs, and readiness"]
  V2 --> D2["Ownership check and revision-bound Vera verdict"]
  D2 -->|"Evidence stale"| T2["Trial recheck, edit if needed"]
  T2 --> D2
  D2 -->|"Verdicts current"| I2["Land streams and run revision-bound join"]
  S --> R["Shared: report evidence, gaps, and approvals"]
  I1 --> R
  I2 --> R
```

Both workflows use isolated worktrees and exclusive write ownership for
parallel writers, an independent Vera verdict per stream, and a separate
combined check. [v1](workflows/v1.md) sequences handoffs through the
coordinator and reviews the actual diffs. [v2](workflows/v2.md) tracks hard
and read-only dependencies, refreshes stale evidence, and binds its join
check to the landed commits. Final merge, push, and deployment require
explicit approval in both workflows.

## Specialized skills

- [Alien Science Ideation](skills/alien-science-ideation/SKILL.md) is installed
  by default. The coordinator loads it only when the user explicitly requests
  alien ideation, cognitively unavailable research directions, or the skill.
- The [weight-space network audit](skills/weight-space-network-audit/SKILL.md)
  supports protocol-based ReLU audits, read-only checkpoint inspection, and
  explicitly requested diagnosis or reversible edits on safe copies.

## Checks

```sh
bash tests/install-e2e.sh
python3 tests/tui-e2e.py
bash tests/workstream-e2e.sh
python3 tests/live-graph.py --self-test
```

These checks exercise the installers with Pi mocked, the terminal UI, the
Git ownership and read-only gates, and offline graph fixtures. The opt-in
live scripts use `tests/live-parallel-smoke.sh` with Antigravity CLI or Claude
Code, and `tests/live-graph.py --live` with Claude Code. The live Q0/Q1
comparison is pending. [Evaluation protocol](docs/workflow.md#v2-evaluation)

## Documentation

- [Workflow and evaluation](docs/workflow.md)
- [Peer messaging by harness](docs/peer-messaging.md)
- [Model and effort guide](docs/model-guide.md)
- [Shared coordinator contract](AGENTS.md) and [worker profiles](agents/)
- [Skills](skills/)
- [Research lineage and acknowledgements](docs/references.md)
