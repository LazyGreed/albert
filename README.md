# Quintet

Haa~? Got a bug for me already? I'm **Denia**, Quintet's coordinator. Tell me what you want fixed or built in Pi, Claude Code, or Antigravity CLI. I'll use your harness's native subagents to get the work done and tell you what we actually verified~♡

## Who I call in

I decide who the task needs, give each worker a clear outcome, and check their results before I report back. A routine fix might only need Felix and a focused test. I know when to leave the rest of the crew alone~ (￣ω￣)

- **Nora** traces tricky bugs, researches missing facts, and checks assumptions.
- **Felix** makes the changes in the files I assign and runs focused checks.
- **Vera** independently reviews the diff and checks the evidence. Felix can celebrate after she's had a look~♡
- **Iris** tries the user-facing behavior to see whether it matches what you asked for.

## Pick an edition

### [v1 (coordinator-centric edition)](https://github.com/LazyGreed/quintet/tree/refs/heads/v1)

Pick v1 if you want me to use my judgment to delegate and sequence the work. Say, “Fix the timezone bug in CSV exports and check dates around midnight.” If you also ask me to fix an unrelated keyboard shortcut, I can run the two changes in parallel in isolated Git worktrees.

I give each writer exclusive ownership of their files and check what they touched. Each stream needs its own independent pass from Vera before I integrate it. Then I check the combined result separately.

### [v2 (graph-engineering edition)](https://github.com/LazyGreed/quintet/tree/refs/heads/v2)

Pick v2 when you want me to track dependencies and review freshness explicitly. Suppose you're adding an API field that a UI needs. I record that dependency in a graph and pin each review to the exact revision and upstream inputs it covered.

Changed the API after review? Sneaky little diff~♡ (¬‿¬) I check which reviews went stale and get them verified again. I pin the separate combined check to the exact integration commit, base commit, and included workstream commits. If any of those move, I recheck the combination.

A one-file fix can still take the short route in v2. I match the review to the risk.

## Install your edition

Clone the branch you want and enter its checkout. That's where the installer lives~

```sh
# v1
git clone --branch v1 https://github.com/LazyGreed/quintet.git quintet-v1
cd quintet-v1
```

```sh
# v2
git clone --branch v2 https://github.com/LazyGreed/quintet.git quintet-v2
cd quintet-v2
```

From that checkout, install for your harness.

- **Pi** requires Pi 1.1.0+ and the subagents package. Run `pi install npm:@tintinweb/pi-subagents`, then `./install.sh --harness pi --scope global`.
- **Claude Code** uses `./install.sh --harness claude --scope global`.
- **Antigravity CLI** uses `./install.sh --harness antigravity --scope global`.

In both **v1** and **v2**, `--scope global` puts me in charge across your projects right away (writing your harness's global instruction file and `PERSONALITY.md` configuration, plus the `quintet` agent in Antigravity). For repo-specific rules or a custom per-project personality, run `--scope project --target /path/to/project`.

Once installed, start a session in the project you want me to work on and describe the outcome in your usual chat.

For project-scoped installs and dry runs, see the [v1 setup guide](https://github.com/LazyGreed/quintet/blob/refs/heads/v1/README.md#install) or the [v2 setup guide](https://github.com/LazyGreed/quintet/blob/refs/heads/v2/README.md#install).

Want me a little less smug? Bold request~♡ For a global install in either edition, edit `PERSONALITY.md` in your Quintet edition checkout. For a project install, edit `PERSONALITY.md` at the root of the target project. Rerun the same install command, then start a new session to load the change. [See my default personality](https://github.com/LazyGreed/quintet/blob/refs/heads/v2/PERSONALITY.md).
