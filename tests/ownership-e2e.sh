#!/usr/bin/env bash
# Regression checks for worktree ownership collection: staged-only edits, unstaged
# edits, untracked files, and both paths of a rename.
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

expect_fail() {
  local want="$1"
  shift
  local rc=0
  "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  if (( rc != 1 )); then
    echo "stdout:" >&2
    cat "$tmp/out" >&2
    echo "stderr:" >&2
    cat "$tmp/err" >&2
    fail "expected exit 1, got $rc for: $*"
  fi
  if ! grep -F -q -- "$want" "$tmp/err"; then
    cat "$tmp/err" >&2
    fail "missing [$want] in ownership failure output"
  fi
  if grep -F -q 'OWNERSHIP PASS' "$tmp/out"; then
    fail "unexpected OWNERSHIP PASS on a failing check"
  fi
}

repo="$tmp/repo"
mkdir -p "$repo/src"
git -C "$repo" init -q
git -C "$repo" config user.name "Albert Test"
git -C "$repo" config user.email "albert-test@example.com"
git -C "$repo" checkout -b main -q
printf 'base\n' > "$repo/src/a.py"
printf 'keep\n' > "$repo/src/b.py"
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

echo "ownership E2E PASS: staged MM, staged AD, unstaged edit, untracked file, rename both paths"
