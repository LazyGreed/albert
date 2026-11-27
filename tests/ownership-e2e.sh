#!/usr/bin/env bash
# Regression checks for worktree ownership across commits, index and working files.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/skills/verification/scripts/check-ownership.sh"
[[ -x "$checker" ]] || { echo "Missing executable checker: $checker" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  echo "ownership-e2e FAIL: $*" >&2
  exit 1
}

expect_pass() {
  local want="$1"
  shift
  local rc=0
  "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  if (( rc != 0 )); then
    echo "stdout:" >&2
    cat "$tmp/out" >&2
    echo "stderr:" >&2
    cat "$tmp/err" >&2
    fail "expected exit 0, got $rc for: $*"
  fi
  if ! grep -F -q -- "$want" "$tmp/out"; then
    cat "$tmp/out" >&2
    fail "missing [$want] in ownership pass output"
  fi
  if grep -F -q 'OWNERSHIP FAIL' "$tmp/out" "$tmp/err"; then
    fail "unexpected OWNERSHIP FAIL in pass output"
  fi
}

expect_reject() {
  local expected_rc="$1" want="$2"
  shift 2
  local rc=0
  "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  if (( rc != expected_rc )); then
    echo "stdout:" >&2
    cat "$tmp/out" >&2
    echo "stderr:" >&2
    cat "$tmp/err" >&2
    fail "expected exit $expected_rc, got $rc for: $*"
  fi
  if ! grep -F -q -- "$want" "$tmp/err"; then
    cat "$tmp/err" >&2
    fail "missing [$want] in ownership failure output"
  fi
  if grep -F -q 'OWNERSHIP PASS' "$tmp/out"; then
    fail "unexpected OWNERSHIP PASS on a failing check"
  fi
}

expect_fail() {
  expect_reject 1 "$@"
}

repo="$tmp/repo"
mkdir -p "$repo/src"
git -C "$repo" init -q
git -C "$repo" config user.name "Albert Test"
git -C "$repo" config user.email "albert-test@example.com"
git -C "$repo" checkout -b main -q
printf 'base\n' > "$repo/src/a.py"
printf 'keep\n' > "$repo/src/b.py"
printf 'tracked\n' > "$repo/src/foreign"
printf 'base\n' > "$repo/src/stat.py"
touch -t 200001010000 "$repo/src/stat.py"
printf '*.log\n' > "$repo/.gitignore"
git -C "$repo" add -A
git -C "$repo" commit -q -m "baseline"
base="$(git -C "$repo" rev-parse HEAD)"

# Confirmed miss: worktree matches base, index does not, status MM.
printf 'head\n' > "$repo/src/a.py"
git -C "$repo" add src/a.py
git -C "$repo" commit -q -m "move a"
move_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'staged\n' > "$repo/src/a.py"
git -C "$repo" add src/a.py
printf 'base\n' > "$repo/src/a.py"
[[ "$(git -C "$repo" status --porcelain)" == "MM src/a.py" ]] || fail "precondition: expected MM src/a.py, got $(git -C "$repo" status --porcelain)"
[[ -z "$(git -C "$repo" diff --name-only "$base")" ]] || fail "precondition: worktree diff against base was not empty"
[[ "$(git -C "$repo" diff --cached --name-only "$base")" == "src/a.py" ]] || fail "precondition: cached diff did not show src/a.py"

expect_pass "OWNERSHIP PASS: 1 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/a.py
grep -F -q '  src/a.py' "$tmp/out" || fail "MM case did not list src/a.py"
if grep -F -q '0 changed paths' "$tmp/out"; then
  fail "MM case still reports 0 changed paths"
fi
expect_fail "src/a.py" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/b.py

# --head stays a committed diff and must not treat the staged index as the commit.
expect_pass "OWNERSHIP PASS: 0 changed paths" \
  "$checker" --base "$move_commit" --head HEAD --repo "$repo" -- src/a.py

git -C "$repo" reset -q --hard "$base"
git -C "$repo" clean -q -fd

# Staged add whose worktree file was removed (AD).
printf 'new\n' > "$repo/src/added.py"
git -C "$repo" add src/added.py
rm -f -- "$repo/src/added.py"
[[ "$(git -C "$repo" status --porcelain)" == "AD src/added.py" ]] || fail "precondition: expected AD src/added.py, got $(git -C "$repo" status --porcelain)"
[[ -z "$(git -C "$repo" diff --name-only --no-renames "$base")" ]] || fail "precondition: AD worktree diff against base was not empty"
expect_pass "OWNERSHIP PASS: 1 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/added.py
grep -F -q '  src/added.py' "$tmp/out" || fail "AD case did not list src/added.py"
expect_fail "src/added.py" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/a.py

git -C "$repo" reset -q --hard "$base"
git -C "$repo" clean -q -fd

# Unstaged edit.
printf 'unstaged\n' > "$repo/src/a.py"
[[ "$(git -C "$repo" status --porcelain)" == " M src/a.py" ]] || fail "precondition: expected unstaged edit, got $(git -C "$repo" status --porcelain)"
expect_pass "OWNERSHIP PASS: 1 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/a.py
grep -F -q '  src/a.py' "$tmp/out" || fail "unstaged edit was not reported"
expect_fail "src/a.py" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/b.py

git -C "$repo" reset -q --hard "$base"

# Untracked non-ignored file. Ignored files stay out of the set.
printf 'note\n' > "$repo/src/note.py"
printf 'ignored\n' > "$repo/debug.log"
expect_pass "OWNERSHIP PASS: 1 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- 'src/*.py'
grep -F -q '  src/note.py' "$tmp/out" || fail "untracked file was not reported"
if grep -F -q 'debug.log' "$tmp/out" "$tmp/err"; then
  fail "ignored file was reported"
fi
expect_fail "src/note.py" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/a.py

rm -f -- "$repo/src/note.py" "$repo/debug.log"

# Worktree rename must list both paths (deletion from diff, new path from untracked).
mv "$repo/src/b.py" "$repo/src/c.py"
expect_pass "OWNERSHIP PASS: 2 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- 'src/'
grep -F -q '  src/b.py' "$tmp/out" || fail "rename did not list old path src/b.py"
grep -F -q '  src/c.py' "$tmp/out" || fail "rename did not list new path src/c.py"

git -C "$repo" reset -q --hard "$base"
git -C "$repo" clean -q -fd

# Staged rename also lists both paths once each.
git -C "$repo" mv src/b.py src/c.py
expect_pass "OWNERSHIP PASS: 2 path(s) verified" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- 'src/'
grep -F -q '  src/b.py' "$tmp/out" || fail "staged rename did not list old path"
grep -F -q '  src/c.py' "$tmp/out" || fail "staged rename did not list new path"

# A staged deletion can cancel a committed addition in a net diff against base.
git -C "$repo" reset -q --hard "$base"
printf 'foreign\n' > "$repo/src/foreign file.py"
git -C "$repo" add -- 'src/foreign file.py'
git -C "$repo" commit -q -m 'add foreign path'
git -C "$repo" rm -q -- 'src/foreign file.py'
printf 'owned\n' > "$repo/src/note.py"
[[ -z "$(git -C "$repo" diff --name-only "$base")" ]] || fail 'precondition: expected canceled worktree diff'
[[ -z "$(git -C "$repo" diff --cached --name-only "$base")" ]] || fail 'precondition: expected canceled staged diff'
expect_fail '  src/foreign file.py' \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/note.py
expect_pass 'OWNERSHIP PASS: 2 path(s) verified' \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- 'src/foreign file.py' src/note.py

# An alternate index must not hide a staged edit in the checkout's actual index.
git -C "$repo" reset -q --hard "$base"
cp -- "$repo/.git/index" "$tmp/alternate-index"
printf 'staged only\n' > "$repo/src/b.py"
git -C "$repo" add -- src/b.py
printf 'keep\n' > "$repo/src/b.py"
expect_fail '  src/b.py' env GIT_INDEX_FILE="$tmp/alternate-index" \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/note.py

git -C "$repo" reset -q --hard "$base"
for flag in assume-unchanged skip-worktree; do
  git -C "$repo" update-index "--$flag" -- src/b.py
  printf 'hidden edit\n' > "$repo/src/b.py"
  expect_reject 2 '  src/b.py' \
    "$checker" --base "$base" --worktree "$repo" --require-changes -- src/note.py
  git -C "$repo" update-index "--no-$flag" -- src/b.py
  git -C "$repo" reset -q --hard "$base"
done

# A monitor that reports no updates must not hide a working file change.
printf '%s\n' '#!/bin/sh' 'printf "token\000"' > "$tmp/fsmonitor"
chmod +x "$tmp/fsmonitor"
git -C "$repo" config core.fsmonitor "$tmp/fsmonitor"
git -C "$repo" config core.fsmonitorHookVersion 2
git -C "$repo" update-index --refresh
git -C "$repo" update-index --fsmonitor-valid -- src/b.py
printf 'unreported edit\n' > "$repo/src/b.py"
expect_fail '  src/b.py' \
  "$checker" --base "$base" --worktree "$repo" --require-changes -- src/note.py
git -C "$repo" config --unset core.fsmonitor
git -C "$repo" reset -q --hard "$base"

# A directory Git cannot read is an incomplete scan, even if Git exits zero.
mkdir -- "$repo/private"
printf 'foreign\n' > "$repo/private/note.py"
(
  trap 'chmod u+rwx -- "$repo/private"' EXIT
  chmod u-rwx -- "$repo/private"
  if [[ ! -r "$repo/private" ]]; then
    expect_reject 2 'could not open directory' \
      "$checker" --base "$base" --worktree "$repo" --require-changes -- src/note.py
  fi
)
rm -rf -- "$repo/private"

# A backslash in an exact pattern stays literal before regex punctuation.
printf 'allowed\n' > "$repo/"'owned\.'
expect_pass '  owned\.' \
  "$checker" --base HEAD --worktree "$repo" -- 'owned\.' src/note.py
printf 'foreign\n' > "$repo/"'owned\X'
expect_fail '  owned\X' \
  "$checker" --base HEAD --worktree "$repo" -- 'owned\.' src/note.py
rm -- "$repo/"'owned\.' "$repo/"'owned\X'

# On a case-sensitive filesystem, Git must report names that differ only in case.
if [[ ! -e "$repo/src/Foreign" ]]; then
  printf 'foreign\n' > "$repo/src/Foreign"
  git -C "$repo" config core.ignoreCase true
  expect_fail '  src/Foreign' "$checker" --base HEAD --worktree "$repo" -- src/note.py
  [[ "$(git -C "$repo" config core.ignoreCase)" == true ]]
  git -C "$repo" config --unset core.ignoreCase
  rm -- "$repo/src/Foreign"
fi

# Equal-size content can change while mtime is restored. Let ctime tick even on
# filesystems with one-second timestamp resolution.
cp -p -- "$repo/src/stat.py" "$tmp/stat-time"
sleep 1
printf 'edit\n' > "$repo/src/stat.py"
touch -r "$tmp/stat-time" "$repo/src/stat.py"
git -C "$repo" config core.trustctime false
git -C "$repo" config core.checkStat minimal
expect_fail '  src/stat.py' "$checker" --base HEAD --worktree "$repo" -- src/note.py
[[ "$(git -C "$repo" config core.trustctime)" == false ]]
[[ "$(git -C "$repo" config core.checkStat)" == minimal ]]
git -C "$repo" config --unset core.trustctime
git -C "$repo" config --unset core.checkStat
git -C "$repo" restore -- src/stat.py

# Gitlink changes must survive Git's submodule diff preferences in both modes.
git -C "$repo" update-index --add --cacheinfo "160000,$base,foreign-submodule"
git -C "$repo" commit -q -m 'add gitlink'
submodule_base="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" update-index --cacheinfo "160000,$submodule_base,foreign-submodule"
git -C "$repo" config diff.ignoreSubmodules all
expect_fail '  foreign-submodule' \
  "$checker" --base "$submodule_base" --worktree "$repo" --require-changes -- src/note.py
git -C "$repo" commit -q -m 'change gitlink'
expect_fail '  foreign-submodule' \
  "$checker" --base "$submodule_base" --head HEAD --repo "$repo" -- src/note.py

# With --repo under the root, diff.relative must not hide other paths.
git -C "$repo" config --unset diff.ignoreSubmodules
git -C "$repo" config diff.relative true
expect_fail '  foreign-submodule' \
  "$checker" --base "$submodule_base" --head HEAD --repo "$repo/src" -- src/note.py
git -C "$repo" config --unset diff.relative

# Compare recorded trees even when Git has a local replacement ref.
git -C "$repo" replace HEAD "$submodule_base"
expect_fail '  foreign-submodule' \
  "$checker" --base "$submodule_base" --head HEAD --repo "$repo" -- src/note.py

# A parent-only diff cannot establish that a populated submodule was fully scanned.
child="$tmp/child"
parent="$tmp/parent"
child_path='child module'
for fixture in "$child" "$parent"; do
  git init -q "$fixture"
  git -C "$fixture" config user.name 'Quintet Test'
  git -C "$fixture" config user.email 'quintet-test@example.com'
  git -C "$fixture" commit -q --allow-empty -m 'base'
done
parent_base="$(git -C "$parent" rev-parse HEAD)"
printf 'base\n' > "$child/tracked"
git -C "$child" add tracked
git -C "$child" commit -q -m 'track file'
# The nested module uses the preceding commit of the same fixture repository.
git -C "$child" -c protocol.file.allow=always submodule add -q "$child" nested
git -C "$child" commit -q -m 'add nested module'
git -C "$parent" -c protocol.file.allow=always submodule add -q "$child" "$child_path"
git -C "$parent" commit -q -m 'add child module'
git -C "$parent" -c protocol.file.allow=always submodule update -q --init --recursive

child_worktree="$parent/$child_path"
nested_worktree="$child_worktree/nested"
for flag in assume-unchanged skip-worktree; do
  git -C "$nested_worktree" update-index "--$flag" -- tracked
  printf 'hidden edit\n' > "$nested_worktree/tracked"
  expect_reject 2 "  $child_path" \
    "$checker" --base HEAD --worktree "$parent" -- owned
  git -C "$nested_worktree" update-index "--no-$flag" -- tracked
  git -C "$nested_worktree" restore -- tracked
done

mkdir -- "$nested_worktree/private"
printf 'hidden\n' > "$nested_worktree/private/file"
(
  trap 'chmod u+rwx -- "$nested_worktree/private"' EXIT
  chmod u-rwx -- "$nested_worktree/private"
  if [[ ! -r "$nested_worktree/private" ]]; then
    expect_reject 2 "  $child_path" \
      "$checker" --base HEAD --worktree "$parent" -- owned
  fi
)
rm -rf -- "$nested_worktree/private"

printf 'unreadable edit\n' > "$child_worktree/tracked"
(
  trap 'chmod u+rwx -- "$child_worktree"' EXIT
  chmod u-rwx -- "$child_worktree"
  if [[ ! -r "$child_worktree" ]]; then
    expect_reject 2 "  $child_path" \
      "$checker" --base HEAD --worktree "$parent" -- owned
  fi
)
expect_pass 'OWNERSHIP PASS: 2 path(s) verified' \
  "$checker" --base "$parent_base" --head HEAD --repo "$parent" -- .gitmodules "$child_path"

git -C "$parent" submodule deinit -q -f -- "$child_path"
expect_pass 'OWNERSHIP PASS: 0 changed paths' \
  "$checker" --base HEAD --worktree "$parent" -- owned
printf 'hidden\n' > "$child_worktree/.leftover"
expect_reject 2 "  $child_path" \
  "$checker" --base HEAD --worktree "$parent" -- owned

echo 'ownership E2E PASS: changed paths, Git scan overrides, and incomplete worktrees'
