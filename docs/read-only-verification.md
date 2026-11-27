# Read-only verification

Run the commands below from the Quintet repository. Set `repo` to the Git worktree under review and keep the snapshot outside that worktree.

```sh
checker="$PWD/skills/verification/scripts/check-readonly.sh"
repo=/path/to/worktree
snapshot=$(mktemp /tmp/quintet-snapshot.XXXXXXXX)
"$checker" snapshot "$repo" > "$snapshot"
# Run the verification commands here.
"$checker" verify "$snapshot" "$repo"
```

`snapshot` records HEAD, hashes of the staged and unstaged diffs, and fingerprints of untracked, non-ignored files. `verify` prints `READONLY_OK` and exits 0 when the snapshots match. It prints `READONLY_VIOLATION` and exits 1 when they differ. Omit the repo argument to use the current directory's Git worktree. Remove the snapshot file when you finish.

## Run a command in the Codex sandbox

Opt in with `run-codex <repo> -- <command> [args...]`:

```sh
"$checker" run-codex "$repo" -- git status --short
```

The helper requires a Codex CLI with named sandbox permission profiles (`codex sandbox -P`). It was tested on Linux with Codex CLI 0.172.0. The command starts at the Git root with network access disabled and a private writable `TMPDIR` that the helper removes afterward. Run test suites that write into the worktree in a disposable copy.

The sandbox applies to the wrapped command and its subprocesses. A Codex child process launched inside it inherits the parent process's restrictions. Bash commands that the harness runs outside the helper retain the native session's privileges. The helper offers no known read-only guarantee for an entire worker session.
