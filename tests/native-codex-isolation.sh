#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
checker="$root/skills/verification/scripts/check-readonly.sh"
fixture="$(mktemp -d /tmp/quintet-codex-test.XXXXXXXX)"
trap 'rm -rf -- "$fixture"' EXIT
fixture="$(cd -- "$fixture" && pwd -P)"
repo="$fixture/project tree"
caller_config="$fixture/caller-codex"
mkdir -p -- "$repo/.codex" "$repo/subdir" "$caller_config"
ln -s -- "$repo" "$fixture/repo-link"

export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
git -C "$repo" init -q
printf 'original\n' > "$repo/tracked"
cat > "$caller_config/config.toml" <<'TOML'
[permissions.quintet_readonly.filesystem]
":root" = "write"
[permissions.quintet_readonly.network]
enabled = true
TOML
cp -- "$caller_config/config.toml" "$repo/.codex/config.toml"
git -C "$repo" add -- tracked .codex/config.toml
git -C "$repo" -c user.name=Test -c user.email=test@example.com commit -qm baseline
printf 'candidate\n' > "$repo/index-candidate"
"$checker" snapshot "$repo" > "$fixture/snapshot"

run_isolated() {
  CODEX_HOME="$caller_config" TMPDIR="$repo/subdir" \
    "$checker" run-codex "$fixture/repo-link/subdir" -- "$@"
}

host_netns=''
if [[ -L /proc/self/ns/net ]]; then
  host_netns="$(readlink /proc/self/ns/net)"
fi
scratch="$(run_isolated "$BASH" -eu -c '
  expect_denied() {
    if "$@"; then
      printf "Expected sandbox to deny %s\n" "$*" >&2
      exit 1
    fi
  }
  [[ "$(pwd -P)" == "$1" ]]
  [[ "$(git status --porcelain)" == "?? index-candidate" ]]
  [[ "$TMPDIR" != "$1/"* && "$TMPDIR" == "$(cd -- "$TMPDIR" && pwd -P)" ]]
  if [[ -n "$3" ]]; then
    netns="$(readlink /proc/self/ns/net)"
    [[ -n "$netns" && "$netns" != "$3" ]]
  fi
  probe="$(mktemp)"
  printf "%s\n" "$4" > "$probe"
  [[ "$(< "$probe")" == "spaced argument" ]]
  expect_denied touch untracked
  expect_denied touch "$2"
  expect_denied bash -c "printf changed >> tracked"
  expect_denied bash -c "printf changed >> .git/index"
  expect_denied git add -- index-candidate
  printf "%s\n" "$TMPDIR"
' test "$repo" "$fixture/outside" "$host_netns" 'spaced argument')"
[[ ! -e "${scratch%/*}" && ! -e "$fixture/outside" ]]
[[ "$(< "$repo/tracked")" == original ]]
[[ -z "$(ls -A -- "$repo/subdir")" ]]
[[ "$(ls -A -- "$caller_config")" == config.toml ]]
cmp -- "$caller_config/config.toml" "$repo/.codex/config.toml"
"$checker" verify "$fixture/snapshot" "$repo"

status=0
scratch="$(run_isolated "$BASH" -c 'printf "%s\n" "$TMPDIR"; exit 37')" || status=$?
[[ "$status" == 37 && -n "$scratch" && ! -e "${scratch%/*}" ]]

status=0
PATH="$fixture/missing-bin" "$BASH" "$checker" run-codex "$repo" -- \
  /bin/bash -c 'touch "$1"' test "$fixture/ran-without-codex" 2> "$fixture/no-codex.log" || status=$?
[[ "$status" == 2 && ! -e "$fixture/ran-without-codex" ]]
grep -q 'requires Codex CLI with sandbox -P support' "$fixture/no-codex.log"
printf 'native Codex isolation PASS\n'
