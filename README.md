# Quintet

Haa~? Got a bug for me already? I'm **Denia**, Quintet's coordinator. Tell me what you want fixed or built in Pi, Claude Code, or Antigravity CLI. I'll use your harness's native subagents to get the work done and tell you what we actually verified~♡

## Who I call in

I decide who the task needs, give each worker a clear outcome, and check their results before I report back. A routine fix might only need Felix and a focused test. I know when to leave the rest of the crew alone~ (￣ω￣)

| Agent | Role | Scope |
| --- | --- | --- |
| **Denia** (customizable) | Delegate, coordinate, verify, report | Main session only; never edits app code |
| **Nora** | Investigate, research, trace root causes | Read-only |
| **Felix** | Implement changes and run focused checks | Exclusive owned files only |
| **Vera** | Review diffs and verification evidence | Read-only |
| **Iris** | Run user-facing acceptance and smoke checks | Read-only on app code |

## Pick an edition

| Edition | Best for | Coordination model | Antigravity ID |
| --- | --- | --- | --- |
| **[v1](https://github.com/LazyGreed/quintet/tree/refs/heads/v1)** | Routine fixes, rapid prototyping, minimal overhead | Coordinator-centric delegation with exclusive ownership and per-stream Vera checks | `albert` |
| **[v2](https://github.com/LazyGreed/quintet/tree/refs/heads/v2)** | Multi-stream work with shared APIs or dependencies | Explicit dependency graph, revision-bound verification (`REF`/`BASE`), stale invalidation, and integration gate | `quintet` |

### [v1 (coordinator-centric edition)](https://github.com/LazyGreed/quintet/tree/refs/heads/v1)

Pick `v1` when you want me to use my judgment to delegate and sequence work. Say, "Fix the timezone bug in CSV exports and check dates around midnight." Ask for an unrelated keyboard shortcut too, and I can run both in parallel in isolated Git worktrees with exclusive file ownership, independent Vera passes, and a separate combined check.

### [v2 (graph-engineering edition)](https://github.com/LazyGreed/quintet/tree/refs/heads/v2)

Pick `v2` when you want explicit dependency tracking and review freshness. Suppose you're adding an API field that a UI needs: I record that dependency in a graph and pin each review to the exact revision and upstream inputs it covered.

Changed the API after review? Sneaky little diff~♡ (¬‿¬) I check which reviews went stale and get them verified again, and I pin the combined check to the exact integration commit, base commit, and included workstream commits. A one-file fix still takes the short route in `v2`.

## Install your edition

Clone the branch you want and enter its checkout. That's where the installer lives~

```sh
# v1 (coordinator-centric)
git clone --branch v1 https://github.com/LazyGreed/quintet.git quintet-v1
cd quintet-v1
```

```sh
# v2 (graph-engineering)
git clone --branch v2 https://github.com/LazyGreed/quintet.git quintet-v2
cd quintet-v2
```

From that checkout, run `./install.sh` for the interactive TUI, or pick a harness directly:

```sh
# Pi (requires Pi 1.1.0+ and the subagents package)
pi install npm:@tintinweb/pi-subagents
./install.sh --harness pi --scope global

# Claude Code
./install.sh --harness claude --scope global

# Antigravity CLI
./install.sh --harness antigravity --scope global
```

In both `v1` and `v2`, `--scope global` puts me in charge across your projects right away (writing your harness's global instruction file and `PERSONALITY.md` configuration). For repo-specific rules or a per-project personality, run `--scope project --target /path/to/project`.

Once installed, start a session in the project you want me to work on and describe the outcome in your usual chat. For project-scoped installs and dry runs, see the [v1 setup guide](https://github.com/LazyGreed/quintet/blob/refs/heads/v1/README.md#install) or the [v2 setup guide](https://github.com/LazyGreed/quintet/blob/refs/heads/v2/README.md#install).

> [!TIP]
> Want me a little less smug? Bold request~♡ For a global install in either edition, edit `PERSONALITY.md` in your Quintet checkout. For a project install, edit `PERSONALITY.md` at the root of the target project. Rerun the same install command, then start a new session to load the change. See my [default personality](https://github.com/LazyGreed/quintet/blob/refs/heads/v2/PERSONALITY.md).
