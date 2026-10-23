# albert

**One voice. Four workers. Your repo.**

Tell Albert what to build, fix, or review. It delegates using your harness's native subagents — almost any harness that has them, including **Pi** and **Claude Code**. No daemon. No dashboard. No database. No tmux.

```text
           you
            │
          albert    plan · delegate · verify · report
            │
      ┌─────┼────────┬──────┐
     nora  felix   vera   iris
    think  build  review  test
```

### the crew

| Agent | Job |
| --- | --- |
| **Albert** | Scope, route, decide, report. Never writes app code. |
| **Nora** | Investigate what isn't clear. |
| **Felix** | Ship the change. Own the checks. |
| **Vera** | Independent review when it matters. |
| **Iris** | Real E2E / smoke acceptance. No invented PASS. |

Work starts from normal conversation. Background work when useful. One writer per checkout. Fix/review loops are bounded. [Workflow details →](docs/workflow.md)

### harnesses

Albert is instructions plus markdown role profiles, so the crew is not tied to one runtime. Any harness with native subagents can run it; `install.sh` automates two of them today:

- **Pi** — `~/.pi/agent` / `.pi`, tintinweb `Agent`. Pi also needs the [tintinweb/pi-subagents](https://github.com/tintinweb/pi-subagents) package: `pi install npm:@tintinweb/pi-subagents`.
- **Claude Code** — `~/.claude` / `.claude`, built-in agents.

Every other harness with native subagents works by copying `AGENTS.md`, `agents/*.md`, and `skills/` wherever it reads instructions — `install.sh` does not automate those. That includes other CLIs, your dotfiles, and bots wired to the same files. Only the delegation mechanics differ; the roles, routing, and verification rules are the same. Model/effort choices are yours — see [model guidance](docs/model-guide.md).

### install

Pi needs **>=1.1.0** and [tintinweb/pi-subagents](https://github.com/tintinweb/pi-subagents):

```sh
pi install npm:@tintinweb/pi-subagents
./install.sh
```

Arrows / `j` `k` · Space / Enter · Esc. Review changes, then install.

**No TUI?**

```sh
./install.sh --harness pi,claude --scope global
./install.sh --harness claude --scope project --target /path/to/repo
./install.sh --harness pi --scope global --with-jev
./install.sh --harness pi,claude --scope project --dry-run
```

Existing instructions stay. Managed blocks update in place; changed files get backups. Model settings untouched. Pi installs fail early if the runtime or tintinweb package is missing. `--with-jev` is opt-in and keeps existing registrations. Jev can send code/diffs to your configured endpoint.

### setup prompt

Paste this to your agent and answer its questions. It handles harness, scope, Jev, and per-agent model/effort.

```text
Set up Albert (https://github.com/LazyGreed/albert) — the agent crew in this repo: AGENTS.md, agents/{nora,felix,vera,iris}.md, and skills/.

Check my current harness and set it up based on the repo guidelines accordingly to the global scope.

Verify by listing the installed agent files, confirm the Albert managed block in AGENTS.md/CLAUDE.md, and report exactly what changed. Mark anything you could not check as NOT RUN.
```

### how it runs

- **Pi** — native `Agent`, `get_subagent_result`, `steer_subagent`. Worker prompts append to project instructions. Albert-only limits stay Albert-only.
- **Claude Code** — built-in agents. Shared `CLAUDE.md`, worker-specific roles.
- **Models** — pick your own. Albert: strong reasoning; Felix/Vera: strong coding/review; Nora/Iris: fit the task. Configure role frontmatter or Pi per-call overrides. No provider lock-in.
- **Reporting** — many workers, one report. Workers lead with a headline, Albert merges a round into a single message, and on Pi the colored widget, FleetView, and `@name` give you the detail on demand. [Details →](docs/workflow.md#reporting-with-several-workers)
- **Skills** — `architecture`, `domain-modeling`, `ui-ux`, `documentation`, `research`, `verification`. Use `verification` for relevant bug, feature, or refactor work; skill loading remains native-harness controlled.
