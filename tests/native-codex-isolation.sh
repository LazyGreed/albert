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
printf '*.log\n' > "$repo/.gitignore"
git -C "$repo" add -- tracked .gitignore .codex/config.toml
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

head_ref="$(git -C "$repo" symbolic-ref --short HEAD)"
printf 'ignored output\n' > "$repo/ignored.log"
"$checker" verify "$fixture/snapshot" "$repo"
for args in '-c other-branch' '--detach'; do
  # These fixtures switch HEAD without changing the commit or tracked files.
  read -r -a switch_args <<< "$args"
  git -C "$repo" switch -q "${switch_args[@]}"
  status=0
  "$checker" verify "$fixture/snapshot" "$repo" > "$fixture/head-change.log" 2>&1 || status=$?
  [[ "$status" == 1 ]]
  grep -Fq 'HEAD ref ' "$fixture/head-change.log"
  git -C "$repo" switch -q "$head_ref"
done
"$checker" verify "$fixture/snapshot" "$repo"

status=0
(cd -- "$repo" && CODEX_HOME="$caller_config" codex sandbox -P :read-only -- \
  "$checker" run-codex "$repo" -- "$BASH" -c 'printf "ran\n"') \
  > "$fixture/nested.out" 2> "$fixture/nested.err" || status=$?
[[ "$status" == 2 && ! -s "$fixture/nested.out" ]]
grep -Fq 'cannot provision sandbox scratch' "$fixture/nested.err"

status=0
scratch="$(run_isolated "$BASH" -c 'printf "%s\n" "$TMPDIR"; exit 37')" || status=$?
[[ "$status" == 37 && -n "$scratch" && ! -e "${scratch%/*}" ]]

status=0
PATH="$fixture/missing-bin" "$BASH" "$checker" run-codex "$repo" -- \
  /bin/bash -c 'touch "$1"' test "$fixture/ran-without-codex" 2> "$fixture/no-codex.log" || status=$?
[[ "$status" == 2 && ! -e "$fixture/ran-without-codex" ]]
grep -q 'requires Codex CLI with sandbox -P support' "$fixture/no-codex.log"

if [[ "$(uname -s)" == Linux ]] && command -v bwrap >/dev/null; then
  mkdir -p "$fixture/etc/codex" "$fixture/sandbox-tmp"
  cp -- "$checker" "$fixture/check-readonly.sh"
  cat > "$fixture/etc/codex/requirements.toml" <<'TOML'
default_permissions = ":workspace"
[allowed_permission_profiles]
":workspace" = true
TOML
  status=0
  bwrap --unshare-net --ro-bind / / --dev /dev --proc /proc \
    --bind "$fixture/sandbox-tmp" /tmp --bind "$fixture" "$fixture" \
    --ro-bind "$fixture/etc" /etc --chdir "$repo" \
    -- "$fixture/check-readonly.sh" run-codex "$repo" -- touch "$fixture/ran-under-workspace" \
    > "$fixture/managed.out" 2> "$fixture/managed.err" || status=$?
  [[ "$status" == 2 && ! -e "$fixture/ran-under-workspace" ]]
  grep -Fq 'cannot confirm the requested sandbox profile' "$fixture/managed.err"
fi
printf 'native Codex isolation PASS\n'
