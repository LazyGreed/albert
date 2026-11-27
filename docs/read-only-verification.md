# Read-only verification

Nora, Vera, and Iris work read-only. Pi and Claude Code profiles grant native read and search tools and omit general command execution. Pi disables extensions in workers without web access and configures the named web extension and exact tool selectors for web-enabled workers. The Pi extension loader can initialize extension factories before filtering which hooks and tools the worker session uses. These are tool controls within a trusted Pi installation. Antigravity profiles list read tools and optional search. Antigravity CLI 1.5.18 recognizes the global plugin, with effective worker tool enforcement still unverified.

Codex CLI 0.172.0 honors the worker role flags disabling `shell_tool` and `request_permissions_tool`. Roles inherit the parent session's sandbox and approval policy. The read-only role instruction is advisory for other tools that the parent allows. In a native probe, the parent’s `read-only` sandbox denied a worker shell write. Shell commands launched directly by a worker use the parent sandbox, while commands sent through `run-codex` use the wrapper profile below. The installer leaves the parent's sandbox and approval configuration in place. [Codex role application](https://github.com/openai/codex/blob/rust-v0.172.0/codex-rs/core/src/agent/role.rs)

## Executable checks

When a reviewer lacks command access, the coordinator independently runs the relevant gates, including `check-ownership.sh` for parallel and v2 graph streams. The coordinator supplies the exact command, worktree/ref, exit status, and output. Vera inspects the actual diff and decides whether the evidence covers the acceptance criteria. If the worker lacks file tools, the coordinator also supplies the revision-bound diff and relevant context.

Run executable Codex review checks through `check-readonly.sh run-codex`, including checks performed by the coordinator on a worker's behalf. The helper requires `codex sandbox -P` and `--include-managed-config`, tested on Linux with Codex CLI 0.172.0.

```sh
checker=/path/to/skills/verification/scripts/check-readonly.sh
repo=/path/to/review-worktree
"$checker" run-codex "$repo" -- git status --short
```

The helper starts the command at the Git root. Its named profile gives the command and its subprocesses filesystem-wide read access subject to OS restrictions, a private writable `TMPDIR` that the helper removes on exit, and disabled network access. It resolves that profile in a temporary `CODEX_HOME` and inherits any OS sandbox restrictions on the process. Codex can substitute a different sandbox when managed requirements are active, so the helper checks the startup configuration and stops if it reports managed requirements or an unrecognized response. On Linux, the native `:read-only` profile blocks creation of the helper's scratch directory. Keep that session profile and have the coordinator run the command through the wrapper. If the coordinator also cannot launch it, report the check as `BLOCKED`. A check that needs to write into a worktree requires an authorized disposable copy and separate execution as acceptance evidence.

## Check worktree integrity

The coordinator saves a snapshot outside the worktree before review and verifies it afterward.

```sh
snapshot=$(mktemp /tmp/quintet-snapshot.XXXXXXXX)
"$checker" snapshot "$repo" > "$snapshot"
# Run the review checks.
"$checker" verify "$snapshot" "$repo"
rm -- "$snapshot"
```

The snapshot covers HEAD commit and symbolic ref or detached state, hashes of the staged and unstaged diffs, and fingerprints of untracked, non-ignored files. It excludes ignored files, other Git refs and metadata, files outside the worktree, and changes reverted between observations. This is an integrity comparison at two points in time. `verify` exits 0 with `READONLY_OK` when the snapshots match and 1 with `READONLY_VIOLATION` when they differ. Omit the repo argument to use the current directory's Git worktree.
