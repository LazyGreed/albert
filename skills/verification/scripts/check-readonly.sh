#!/usr/bin/env bash
# Mechanical checkout-integrity snapshot and verification for read-only specialists.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  check-readonly.sh snapshot [repo-dir]
  check-readonly.sh verify <snapshot-file> [repo-dir]

Commands:
  snapshot [repo-dir]               Write a deterministic checkout snapshot to stdout
                                    (HEAD + staged binary diff sha256 + unstaged binary
                                    diff sha256 + sorted untracked non-ignored files).
  verify <snapshot-file> [repo-dir] Compare current checkout state against <snapshot-file>.
                                    Exits 0 with READONLY_OK if unchanged, or exits 1 with
                                    READONLY_VIOLATION and status details if modified.
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
cleanup() {
  local f
  for f in "${tmp_files[@]+"${tmp_files[@]}"}"; do
    rm -f -- "$f"
  done
}
trap cleanup EXIT

emit_snapshot() {
  local top="$1"
  local head staged_sha unstaged_sha
  head="$(git -C "$top" rev-parse --verify HEAD 2>/dev/null || echo 'UNBORN')"
  staged_sha="$(git -C "$top" -c core.quotePath=false diff --cached --binary --no-ext-diff | sha256_stream)"
  unstaged_sha="$(git -C "$top" -c core.quotePath=false diff --binary --no-ext-diff | sha256_stream)"

  printf 'HEAD %s\n' "$head"
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
  if ! grep -q '^HEAD ' "$snap_file" || ! grep -q '^STAGED_DIFF_SHA256 ' "$snap_file" || ! grep -q '^UNSTAGED_DIFF_SHA256 ' "$snap_file"; then
    echo "check-readonly: invalid snapshot file: $snap_file" >&2
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

  local old_head new_head old_staged new_staged old_unstaged new_unstaged
  old_head="$(awk '/^HEAD /{print $2; exit}' "$snap_file")"
  new_head="$(awk '/^HEAD /{print $2; exit}' "$current_file")"
  old_staged="$(awk '/^STAGED_DIFF_SHA256 /{print $2; exit}' "$snap_file")"
  new_staged="$(awk '/^STAGED_DIFF_SHA256 /{print $2; exit}' "$current_file")"
  old_unstaged="$(awk '/^UNSTAGED_DIFF_SHA256 /{print $2; exit}' "$snap_file")"
  new_unstaged="$(awk '/^UNSTAGED_DIFF_SHA256 /{print $2; exit}' "$current_file")"

  local reasons=()
  [[ "$old_head" == "$new_head" ]] || reasons+=("HEAD ${old_head}->${new_head}")
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
    if (($# > 2)); then
      echo "check-readonly: snapshot accepts at most one [repo-dir] argument" >&2
      exit 2
    fi
    repo_dir="${2:-.}"
    top="$(resolve_worktree "$repo_dir")"
    emit_snapshot "$top"
    ;;
  verify)
    if (($# < 2 || $# > 3)); then
      echo "check-readonly: verify requires <snapshot-file> [repo-dir]" >&2
      exit 2
    fi
    snap_file="$2"
    repo_dir="${3:-.}"
    top="$(resolve_worktree "$repo_dir")"
    verify_snapshot "$snap_file" "$top"
    ;;
  *)
    echo "check-readonly: unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
