#!/usr/bin/env bash
# Verify that changed (and optionally untracked) paths stay within declared WRITE OWNERSHIP patterns.
set -euo pipefail

# Discover the repository and index for the supplied directory, including in Git hooks.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_INDEX_FILE \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH \
  GIT_NAMESPACE GIT_PREFIX GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE \
  GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
export GIT_OPTIONAL_LOCKS=0 GIT_NO_REPLACE_OBJECTS=1

usage() {
  cat <<'USAGE'
Usage: check-ownership.sh --base <ref> [--head <ref>] [--worktree <dir>] [--repo <dir>] [--require-changes] -- <allow-pattern>...

Options:
  --base <ref>        Base commit/ref to diff against (required).
  --head <ref>        Head commit/ref when checking committed diff (default: HEAD).
                      Cannot be combined with --worktree.
  --worktree <dir>    Check the union of base-to-HEAD, staged, unstaged, and
                      non-ignored untracked paths in <dir>.
  --repo <dir>        Git repository directory when --worktree is not set (default: .).
  --require-changes   Fail (exit 1) if zero changed paths are found.
  -h, --help          Show this help message.

Paths are relative to the repository root. Submodules are checked at their
path in the parent repository. Use a stable worktree and index during the scan.
A worktree with assume-unchanged or skip-worktree entries exits 2.

Allow patterns:
  Exact paths         AGENTS.md, src/app.py
  Directory prefixes  server/validation/ or server/validation/**
  Globs               tests/*.sh (* stays within one segment), **/*.md, server/**/*.ts
USAGE
}

base=""
head_ref=""
worktree=""
repo_dir="."
require_changes=0
patterns=()

while (($#)); do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || { echo "check-ownership: --base requires an argument" >&2; exit 2; }
      base="$2"
      shift 2
      ;;
    --head)
      [[ $# -ge 2 ]] || { echo "check-ownership: --head requires an argument" >&2; exit 2; }
      head_ref="$2"
      shift 2
      ;;
    --worktree)
      [[ $# -ge 2 ]] || { echo "check-ownership: --worktree requires an argument" >&2; exit 2; }
      worktree="$2"
      shift 2
      ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "check-ownership: --repo requires an argument" >&2; exit 2; }
      repo_dir="$2"
      shift 2
      ;;
    --require-changes)
      require_changes=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($#)); do
        patterns+=("$1")
        shift
      done
      break
      ;;
    -*)
      echo "check-ownership: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      patterns+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$base" ]]; then
  echo "check-ownership: --base <ref> is required" >&2
  usage >&2
  exit 2
fi

if [[ -n "$worktree" && -n "$head_ref" ]]; then
  echo "check-ownership: --head cannot be combined with --worktree" >&2
  exit 2
fi

if [[ ${#patterns[@]} -eq 0 ]]; then
  echo "check-ownership: at least one <allow-pattern> is required" >&2
  usage >&2
  exit 2
fi

git_dir="$repo_dir"
if [[ -n "$worktree" ]]; then
  git_dir="$worktree"
fi

if [[ ! -d "$git_dir" ]]; then
  echo "check-ownership: directory not found: $git_dir" >&2
  exit 2
fi

if [[ -n "$worktree" ]]; then
  if [[ "$(git -C "$git_dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    echo "check-ownership: not a git work tree: $git_dir" >&2
    exit 2
  fi
  git_dir="$(git -C "$git_dir" rev-parse --show-toplevel)"
else
  if ! git -C "$git_dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "check-ownership: not a git repository: $git_dir" >&2
    exit 2
  fi
fi

if ! base_commit="$(git -C "$git_dir" rev-parse --verify --end-of-options "${base}^{commit}" 2>/dev/null)"; then
  echo "check-ownership: invalid --base ref: $base" >&2
  exit 2
fi

head_ref="${head_ref:-HEAD}"
if ! head_commit="$(git -C "$git_dir" rev-parse --verify --end-of-options "${head_ref}^{commit}" 2>/dev/null)"; then
  echo "check-ownership: invalid head ref: $head_ref" >&2
  exit 2
fi

# Convert a path glob pattern into an anchored POSIX ERE.
glob_to_ere() {
  local pat="$1"
  while [[ "$pat" == ./* ]]; do
    pat="${pat#./}"
  done
  if [[ -z "$pat" ]]; then
    echo "check-ownership: empty allow-pattern is not valid" >&2
    return 2
  fi
  if [[ "$pat" == */ ]]; then
    pat="${pat}**"
  fi

  local len=${#pat}
  local i=0
  local ere="^"
  local ch prev

  while (( i < len )); do
    if (( i + 3 <= len )) && [[ "${pat:i:3}" == "**/" ]]; then
      prev=""
      if (( i > 0 )); then
        prev="${pat:i-1:1}"
      fi
      if (( i == 0 )) || [[ "$prev" == "/" ]]; then
        ere+="(.*/)?"
        (( i += 3 ))
        continue
      fi
    fi

    if (( i + 2 <= len )) && [[ "${pat:i:2}" == "**" ]]; then
      ere+=".*"
      (( i += 2 ))
      continue
    fi

    ch="${pat:i:1}"
    case "$ch" in
      '*') ere+="[^/]*" ;;
      '?') ere+="[^/]" ;;
      '.'|'+'|'('|')'|'{'|'}'|'^'|'$'|'|'|'\\'|'['|']') ere+="\\$ch" ;;
      *) ere+="$ch" ;;
    esac
    (( i += 1 ))
  done

  ere+="$"
  printf '%s\n' "$ere"
}

regexes=()
for pat in "${patterns[@]}"; do
  re="$(glob_to_ere "$pat")" || exit $?
  regexes+=("$re")
done

changed_paths=()
add_unique_path() {
  local candidate="$1"
  local existing
  for existing in "${changed_paths[@]+"${changed_paths[@]}"}"; do
    if [[ "$existing" == "$candidate" ]]; then
      return 0
    fi
  done
  changed_paths+=("$candidate")
}

tmp_git_out="$(mktemp -d)"
trap 'rm -rf -- "$tmp_git_out"' EXIT

run_git_scan() {
  # Git can warn about unreadable paths and still exit successfully.
  if ! git -C "$git_dir" -c core.fsmonitor=false "$@" > "$tmp_git_out/paths" 2> "$tmp_git_out/errors" ||
    [[ -s "$tmp_git_out/errors" ]]; then
    cat "$tmp_git_out/errors" >&2
    printf 'check-ownership: incomplete Git scan (%s)\n' "$*" >&2
    return 2
  fi
}

collect_git_z_paths() {
  local path
  run_git_scan "$@"
  while IFS= read -r -d '' path; do
    add_unique_path "$path"
  done < "$tmp_git_out/paths"
}

if [[ -n "$worktree" ]]; then
  run_git_scan ls-files -v -z
  while IFS= read -r -d '' entry; do
    # Lowercase tags are assume-unchanged. S is skip-worktree.
    if [[ "$entry" == [a-zS]\ * ]]; then
      printf 'check-ownership: assume-unchanged or skip-worktree path prevents a complete scan\n  %s\n' "${entry:2}" >&2
      exit 2
    fi
  done < "$tmp_git_out/paths"
fi

# Disabling rename detection includes both names. Compare each pair of adjacent
# states so an index or worktree change cannot cancel an earlier change.
diff_options=(--name-only --no-renames --no-relative --ignore-submodules=none -z)
collect_git_z_paths diff "${diff_options[@]}" "$base_commit" "$head_commit" --
if [[ -n "$worktree" ]]; then
  collect_git_z_paths diff --cached "${diff_options[@]}" "$head_commit" --
  collect_git_z_paths diff "${diff_options[@]}" --
  collect_git_z_paths ls-files --others --exclude-standard -z
fi

total=${#changed_paths[@]}
if (( total == 0 )); then
  if (( require_changes )); then
    echo "OWNERSHIP FAIL: no changed paths found (--require-changes)" >&2
    exit 1
  fi
  echo "OWNERSHIP PASS: 0 changed paths"
  exit 0
fi

out_of_scope=()
for path in "${changed_paths[@]}"; do
  matched=0
  for re in "${regexes[@]}"; do
    if [[ "$path" =~ $re ]]; then
      matched=1
      break
    fi
  done
  if (( !matched )); then
    out_of_scope+=("$path")
  fi
done

if (( ${#out_of_scope[@]} > 0 )); then
  printf 'OWNERSHIP FAIL: %d out-of-scope path(s) (checked %d total)\n' "${#out_of_scope[@]}" "$total" >&2
  for path in "${out_of_scope[@]}"; do
    printf '  %s\n' "$path" >&2
  done
  exit 1
fi

printf 'OWNERSHIP PASS: %d path(s) verified\n' "$total"
for path in "${changed_paths[@]}"; do
  printf '  %s\n' "$path"
done
exit 0
