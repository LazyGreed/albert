# albert

**One voice. Four workers. Your repo.**

Tell Albert what to build, fix, or review. It delegates using your existing **Pi** or **Claude Code** agents. No daemon. No dashboard. No database. No tmux.

```text
           you
            │
          albert    plan · delegate · verify · report
            │
      ┌─────┼─────┬─────┐
     nora  felix  vera  iris
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

### how it runs

- **Pi** — native `Agent`, `get_subagent_result`, `steer_subagent`. Worker prompts append to project instructions. Albert-only limits stay Albert-only.
- **Claude Code** — built-in agents. Shared `CLAUDE.md`, worker-specific roles.
- **Models** — pick your own. Albert: strong reasoning; Felix/Vera: strong coding/review; Nora/Iris: fit the task. Configure role frontmatter or Pi per-call overrides. No provider lock-in.
- **Skills** — `architecture`, `domain-modeling`, `ui-ux`, `documentation`, `research`. Nothing auto-loaded beyond native harness behavior.

### check

```sh
./tests/install-e2e.sh
python3 ./tests/tui-e2e.py
```

No test-per-function ritual. E2E where observable, focused regression checks for real invariants. Missing checks = **NOT RUN**. No auto merge, release, or deploy.
