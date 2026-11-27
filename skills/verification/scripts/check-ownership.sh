#!/usr/bin/env bash
# Verify that changed (and optionally untracked) paths stay within declared WRITE OWNERSHIP patterns.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: check-ownership.sh --base <ref> [--head <ref>] [--worktree <dir>] [--repo <dir>] [--require-changes] -- <allow-pattern>...

Options:
  --base <ref>        Base commit/ref to diff against (required).
  --head <ref>        Head commit/ref when checking committed diff (default: HEAD).
                      Cannot be combined with --worktree.
  --worktree <dir>    Inspect uncommitted + staged + untracked (non-ignored) files
                      in <dir> relative to --base.
  --repo <dir>        Git repository directory when --worktree is not set (default: .).
  --require-changes   Fail (exit 1) if zero changed paths are found.
  -h, --help          Show this help message.

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
worktree_top=""
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
  worktree_top="$(git -C "$git_dir" rev-parse --show-toplevel)"
else
  if ! git -C "$git_dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "check-ownership: not a git repository: $git_dir" >&2
    exit 2
  fi
fi

if ! git -C "$git_dir" rev-parse --verify "${base}^{commit}" >/dev/null 2>&1; then
  echo "check-ownership: invalid --base ref: $base" >&2
  exit 2
fi

if [[ -z "$worktree" ]]; then
  head_ref="${head_ref:-HEAD}"
  if ! git -C "$git_dir" rev-parse --verify "${head_ref}^{commit}" >/dev/null 2>&1; then
    echo "check-ownership: invalid --head ref: $head_ref" >&2
    exit 2
  fi
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

tmp_git_out=""
cleanup_tmp_git_out() {
  if [[ -n "$tmp_git_out" ]]; then
    rm -f -- "$tmp_git_out"
  fi
}
trap cleanup_tmp_git_out EXIT

collect_git_z_paths() {
  local rc=0
  local path
  tmp_git_out="${tmp_git_out:-$(mktemp)}"
  "$@" > "$tmp_git_out" || rc=$?
  if (( rc != 0 )); then
    return "$rc"
  fi
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] && add_unique_path "$path"
  done < "$tmp_git_out"
}

if [[ -n "$worktree" ]]; then
  # Union worktree-vs-base, index-vs-base, and untracked files. Index-vs-base is
  # required when the worktree matches base but the index does not (status MM or AD).
  # --no-renames keeps both paths of a rename; paths are de-duplicated below.
  collect_git_z_paths git -C "$worktree_top" -c core.quotePath=false diff --name-only --no-renames -z "$base"
  collect_git_z_paths git -C "$worktree_top" -c core.quotePath=false diff --cached --name-only --no-renames -z "$base"
  collect_git_z_paths git -C "$worktree_top" -c core.quotePath=false ls-files --others --exclude-standard -z
else
  collect_git_z_paths git -C "$git_dir" -c core.quotePath=false diff --name-only --no-renames -z "$base" "$head_ref"
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
