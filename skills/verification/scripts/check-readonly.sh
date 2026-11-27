#!/usr/bin/env bash
# Checkout integrity checks and Codex command isolation for read-only specialists.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  check-readonly.sh snapshot [repo-dir]
  check-readonly.sh verify <snapshot-file> [repo-dir]
  check-readonly.sh run-codex <repo-dir> -- <command> [args ...]

Commands:
  snapshot [repo-dir]               Write a deterministic checkout snapshot to stdout
                                    (HEAD commit and ref, tracked diff hashes, and
                                    fingerprints of untracked non-ignored files).
  verify <snapshot-file> [repo-dir] Compare current checkout state against <snapshot-file>.
                                    Exits 0 with READONLY_OK if unchanged, or exits 1 with
                                    READONLY_VIOLATION and status details if modified.
  run-codex <repo-dir> -- <command> [args ...]
                                    Run a command at the Git root in the Codex sandbox.
                                    Only its private TMPDIR is writable. Network is disabled.
USAGE
}

sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 | awk '{print $NF}'
  else
    echo "check-readonly: sha256sum or shasum is required" >&2
    return 2
  fi
}

resolve_worktree() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "check-readonly: directory not found: $dir" >&2
    return 2
  fi
  if [[ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" != "true" ]]; then
    echo "check-readonly: not a git work tree: $dir" >&2
    return 2
  fi
  git -C "$dir" rev-parse --show-toplevel
}

tmp_files=()
run_dir=''
cleanup() {
  local f
  for f in "${tmp_files[@]+"${tmp_files[@]}"}"; do
    rm -f -- "$f"
  done
  if [[ -n "$run_dir" ]]; then
    rm -rf -- "$run_dir" || printf 'check-readonly: could not remove %s\n' "$run_dir" >&2
  fi
}
trap cleanup EXIT

run_codex() {
  local repo_dir="$1" top temp_base scratch profile startup
  local startup_without_requirements='^\{"appServerVersion":"[0-9A-Za-z.+-]+","configRequirements":\{"supportsIndependentSpeedModes":(true|false),"requirements":null\}\}$'
  shift
  if ! command -v codex >/dev/null 2>&1; then
    echo 'check-readonly: run-codex requires Codex CLI with sandbox -P support and startup configuration inspection (tested with 0.172.0)' >&2
    return 2
  fi

  top="$(resolve_worktree "$repo_dir")"
  top="$(cd -P -- "$top" && pwd -P)"
  temp_base="$(cd -P -- /tmp && pwd -P)"
  if [[ "$temp_base/" == "${top%/}/"* ]]; then
    echo 'check-readonly: the Git root contains the system temporary directory' >&2
    return 2
  fi
  if [[ ! "$temp_base" =~ ^/[a-zA-Z0-9_./-]+$ ]]; then
    echo 'check-readonly: unsupported physical path for the system temporary directory' >&2
    return 2
  fi

  if ! run_dir="$(mktemp -d "$temp_base/quintet-readonly.XXXXXXXX")"; then
    echo 'check-readonly: cannot provision sandbox scratch. Ask the coordinator to run this check through run-codex.' >&2
    return 2
  fi
  scratch="$run_dir/scratch"
  profile="quintet_readonly_${run_dir##*.}"
  mkdir -m 700 -- "$scratch"
  cat > "$run_dir/config.toml" <<TOML
default_permissions = "$profile"
[permissions.$profile.filesystem]
":root" = "read"
"$scratch" = "write"
[permissions.$profile.network]
enabled = false
TOML

  # Resolve the native profile away from the target. Enter the tree after sandboxing.
  (
    cd -- "$run_dir"
    export CODEX_HOME="$run_dir" TMPDIR="$scratch"
    # A managed policy can silently replace an explicit -P selection with its default.
    if ! startup="$(codex app-server --print-startup-config)" ||
      [[ ! "$startup" =~ $startup_without_requirements ]]; then
      echo 'check-readonly: cannot confirm the requested sandbox profile under Codex startup requirements. No command ran.' >&2
      return 2
    fi
    codex sandbox --include-managed-config -P "$profile" -- \
      "$BASH" -c 'cd -- "$1" && shift && exec -- "$@"' check-readonly "$top" "$@"
  )
}

emit_snapshot() {
  local top="$1"
  local head head_ref staged_sha unstaged_sha
  head="$(git -C "$top" rev-parse --verify HEAD 2>/dev/null || echo 'UNBORN')"
  head_ref="$(git -C "$top" symbolic-ref --quiet HEAD || echo 'DETACHED')"
  staged_sha="$(git -C "$top" -c core.quotePath=false diff --cached --binary --no-ext-diff | sha256_stream)"
  unstaged_sha="$(git -C "$top" -c core.quotePath=false diff --binary --no-ext-diff | sha256_stream)"

  printf 'HEAD %s\n' "$head"
  printf 'HEAD_REF %s\n' "$head_ref"
  printf 'STAGED_DIFF_SHA256 %s\n' "$staged_sha"
  printf 'UNSTAGED_DIFF_SHA256 %s\n' "$unstaged_sha"

  local untracked_list path kind entry_sha encoded_path
  untracked_list="$(mktemp)"
  tmp_files+=("$untracked_list")
  git -C "$top" -c core.quotePath=false ls-files --others --exclude-standard -z | LC_ALL=C sort -z > "$untracked_list"
  while IFS= read -r -d '' path; do
    [[ -n "$path" ]] || continue
    if [[ -L "$top/$path" ]]; then
      kind="symlink"
      entry_sha="$(printf '%s' "$(readlink -- "$top/$path")" | sha256_stream)"
    elif [[ -f "$top/$path" ]]; then
      kind="file"
      entry_sha="$(sha256_stream < "$top/$path")"
    else
      kind="other"
      entry_sha="$(printf '%s' "$path" | sha256_stream)"
    fi
    printf -v encoded_path '%q' "$path"
    printf 'UNTRACKED %s %s %s\n' "$kind" "$entry_sha" "$encoded_path"
  done < "$untracked_list"
}

verify_snapshot() {
  local snap_file="$1" top="$2"
  if [[ ! -f "$snap_file" ]]; then
    echo "check-readonly: snapshot file not found: $snap_file" >&2
    return 2
  fi
  if ! grep -q '^HEAD ' "$snap_file" || ! grep -q '^HEAD_REF ' "$snap_file" ||
    ! grep -q '^STAGED_DIFF_SHA256 ' "$snap_file" || ! grep -q '^UNSTAGED_DIFF_SHA256 ' "$snap_file"; then
    echo "check-readonly: invalid or outdated snapshot; take a new snapshot: $snap_file" >&2
    return 2
  fi

  local current_file
  current_file="$(mktemp)"
  tmp_files+=("$current_file")
  emit_snapshot "$top" > "$current_file"

  if cmp -s "$snap_file" "$current_file"; then
    local head_val
    head_val="$(awk '/^HEAD /{print $2; exit}' "$current_file")"
    printf 'READONLY_OK: HEAD=%s (checkout unchanged)\n' "$head_val"
    return 0
  fi

  local old_head new_head old_ref new_ref old_staged new_staged old_unstaged new_unstaged
  old_head="$(awk '/^HEAD /{print $2; exit}' "$snap_file")"
  new_head="$(awk '/^HEAD /{print $2; exit}' "$current_file")"
  old_ref="$(awk '/^HEAD_REF /{print $2; exit}' "$snap_file")"
  new_ref="$(awk '/^HEAD_REF /{print $2; exit}' "$current_file")"
  old_staged="$(awk '/^STAGED_DIFF_SHA256 /{print $2; exit}' "$snap_file")"
  new_staged="$(awk '/^STAGED_DIFF_SHA256 /{print $2; exit}' "$current_file")"
  old_unstaged="$(awk '/^UNSTAGED_DIFF_SHA256 /{print $2; exit}' "$snap_file")"
  new_unstaged="$(awk '/^UNSTAGED_DIFF_SHA256 /{print $2; exit}' "$current_file")"

  local reasons=()
  [[ "$old_head" == "$new_head" ]] || reasons+=("HEAD ${old_head}->${new_head}")
  [[ "$old_ref" == "$new_ref" ]] || reasons+=("HEAD ref ${old_ref}->${new_ref}")
  [[ "$old_staged" == "$new_staged" ]] || reasons+=("staged diff changed")
  [[ "$old_unstaged" == "$new_unstaged" ]] || reasons+=("unstaged diff changed")

  local old_untracked new_untracked
  old_untracked="$(mktemp)"
  new_untracked="$(mktemp)"
  tmp_files+=("$old_untracked" "$new_untracked")
  grep '^UNTRACKED ' "$snap_file" > "$old_untracked" || true
  grep '^UNTRACKED ' "$current_file" > "$new_untracked" || true
  if ! cmp -s "$old_untracked" "$new_untracked"; then
    reasons+=("untracked files changed")
  fi

  local reason_str="snapshot mismatch"
  if (( ${#reasons[@]} > 0 )); then
    reason_str="$(printf '%s; ' "${reasons[@]}")"
    reason_str="${reason_str%; }"
  fi

  printf 'READONLY_VIOLATION: checkout modified (%s)\n' "$reason_str" >&2
  git -C "$top" -c core.quotePath=false status --short --untracked-files=all >&2 || true
  return 1
}

if (($# == 0)); then
  usage >&2
  exit 2
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
  snapshot)
    export GIT_OPTIONAL_LOCKS=0
    if (($# > 2)); then
      echo "check-readonly: snapshot accepts at most one [repo-dir] argument" >&2
      exit 2
    fi
    repo_dir="${2:-.}"
    top="$(resolve_worktree "$repo_dir")"
    emit_snapshot "$top"
    ;;
  verify)
    export GIT_OPTIONAL_LOCKS=0
    if (($# < 2 || $# > 3)); then
      echo "check-readonly: verify requires <snapshot-file> [repo-dir]" >&2
      exit 2
    fi
    snap_file="$2"
    repo_dir="${3:-.}"
    top="$(resolve_worktree "$repo_dir")"
    verify_snapshot "$snap_file" "$top"
    ;;
  run-codex)
    if (($# < 4)) || [[ "$3" != -- ]]; then
      echo 'check-readonly: run-codex requires <repo-dir> -- <command> [args ...]' >&2
      exit 2
    fi
    repo_dir="$2"
    shift 3
    run_codex "$repo_dir" "$@"
    ;;
  *)
    echo "check-readonly: unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
