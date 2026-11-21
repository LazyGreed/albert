#!/usr/bin/env bash
# Deterministic E2E test for parallel git worktrees, mechanical ownership verification,
# out-of-scope blocking (edited + untracked), landing on integration/task, and combined tests.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/skills/verification/scripts/check-ownership.sh"
[[ -x "$checker" ]] || { echo "Missing executable checker: $checker" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p "$repo/src" "$repo/tests"

git -C "$repo" init -q
git -C "$repo" config user.name "Albert Test"
git -C "$repo" config user.email "albert-test@example.com"
git -C "$repo" checkout -b main -q

cat > "$repo/.gitignore" <<'EOF'
*.log
__pycache__/
EOF

cat > "$repo/src/__init__.py" <<'EOF'
EOF

cat > "$repo/src/a.py" <<'EOF'
def add_one(x: int) -> int:
    return x
EOF

cat > "$repo/src/b.py" <<'EOF'
def shout(text: str) -> str:
    return text
EOF

cat > "$repo/tests/test_a.py" <<'EOF'
import unittest
from src.a import add_one


class TestA(unittest.TestCase):
    def test_placeholder(self):
        self.assertEqual(add_one(1), 1)
EOF

cat > "$repo/tests/test_b.py" <<'EOF'
import unittest
from src.b import shout


class TestB(unittest.TestCase):
    def test_placeholder(self):
        self.assertEqual(shout("hi"), "hi")
EOF

cat > "$repo/tests/test_all.py" <<'EOF'
import unittest
from src.a import add_one
from src.b import shout


class TestAll(unittest.TestCase):
    def test_combined(self):
        self.assertEqual(f"{shout('ok')}:{add_one(4)}", "OK:5")
EOF

git -C "$repo" add -A
git -C "$repo" commit -q -m "chore: baseline"
base_ref="$(git -C "$repo" rev-parse HEAD)"

wt_a="$tmp/wt-stream-a"
wt_b="$tmp/wt-stream-b"
git -C "$repo" worktree add -q -b wt/stream-a "$wt_a" "$base_ref"
git -C "$repo" worktree add -q -b wt/stream-b "$wt_b" "$base_ref"

# Clean worktree: passes without --require-changes, fails with --require-changes.
"$checker" --base "$base_ref" --worktree "$wt_a" -- src/a.py > "$tmp/clean-ok"
grep -q 'OWNERSHIP PASS: 0 changed paths' "$tmp/clean-ok"
if "$checker" --base "$base_ref" --worktree "$wt_a" --require-changes -- src/a.py > "$tmp/clean-req" 2>&1; then
  echo "Expected --require-changes to fail on clean worktree" >&2
  exit 1
fi

# Stream A: valid unstaged edit + staged new file + untracked test + ignored file.
cat > "$wt_a/src/a.py" <<'EOF'
from src.a_helper import increment


def add_one(x: int) -> int:
    return increment(x)
EOF
cat > "$wt_a/src/a_helper.py" <<'EOF'
def increment(x: int) -> int:
    return x + 1
EOF
git -C "$wt_a" add src/a_helper.py

cat > "$wt_a/tests/test_a.py" <<'EOF'
import unittest
from src.a import add_one


class TestA(unittest.TestCase):
    def test_add_one(self):
        self.assertEqual(add_one(4), 5)
EOF

cat > "$wt_a/tests/test_a_extra.py" <<'EOF'
import unittest
from src.a_helper import increment


class TestAExtra(unittest.TestCase):
    def test_increment(self):
        self.assertEqual(increment(9), 10)
EOF

# Gitignored file must not trigger an ownership failure.
echo "ignored log" > "$wt_a/debug.log"

"$checker" --base "$base_ref" --worktree "$wt_a" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' > "$tmp/stream-a-pass"
grep -q 'OWNERSHIP PASS: 4 path(s) verified' "$tmp/stream-a-pass"

# Out-of-scope edit (e.g. formatter modifying stream B's file) must block.
echo "# formatted" >> "$wt_a/src/b.py"
if "$checker" --base "$base_ref" --worktree "$wt_a" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' > "$tmp/oos-edit.out" 2> "$tmp/oos-edit.err"; then
  echo "Expected out-of-scope edit to fail ownership check" >&2
  exit 1
fi
grep -q 'src/b.py' "$tmp/oos-edit.err"
git -C "$wt_a" checkout -- src/b.py

# Out-of-scope untracked file must block.
echo "stray note" > "$wt_a/stray.md"
if "$checker" --base "$base_ref" --worktree "$wt_a" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' > "$tmp/oos-untracked.out" 2> "$tmp/oos-untracked.err"; then
  echo "Expected out-of-scope untracked file to fail ownership check" >&2
  exit 1
fi
grep -q 'stray.md' "$tmp/oos-untracked.err"
rm -f "$wt_a/stray.md"

# Glob semantics: * stays within one segment; ** matches across segments and root files; dir/ prefix is segment-bounded.
mkdir -p "$wt_a/tests/nested" "$wt_a/docs" "$wt_a/src2"
touch "$wt_a/tests/nested/deep.py" "$wt_a/NOTES.md" "$wt_a/docs/guide.md" "$wt_a/src2/other.py"

if "$checker" --base "$base_ref" --worktree "$wt_a" -- \
  'src/' 'tests/*.py' '**/*.md' > "$tmp/glob-single.out" 2> "$tmp/glob-single.err"; then
  echo "Expected tests/*.py not to match tests/nested/deep.py and src/ not to match src2/other.py" >&2
  exit 1
fi
grep -q 'tests/nested/deep.py' "$tmp/glob-single.err"
grep -q 'src2/other.py' "$tmp/glob-single.err"
! grep -q 'NOTES.md' "$tmp/glob-single.err"
! grep -q 'docs/guide.md' "$tmp/glob-single.err"

"$checker" --base "$base_ref" --worktree "$wt_a" -- \
  'src/' 'src2/*.py' 'tests/**/*.py' '**/*.md' > "$tmp/glob-multi.out"
grep -q 'OWNERSHIP PASS:' "$tmp/glob-multi.out"

rm -rf "$wt_a/tests/nested" "$wt_a/docs" "$wt_a/src2" "$wt_a/NOTES.md"

# Subdirectory invocation (--worktree . from sub/) must resolve repo-root-relative paths across the whole worktree.
mkdir -p "$wt_a/sub"
echo "in sub" > "$wt_a/sub/in_sub.py"
(cd "$wt_a/sub" && "$checker" --base "$base_ref" --worktree . --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' sub/in_sub.py) > "$tmp/subdir-pass"
grep -q 'OWNERSHIP PASS: 5 path(s) verified' "$tmp/subdir-pass"
grep -q '^  sub/in_sub\.py$' "$tmp/subdir-pass"

echo "stray outside sub" > "$wt_a/outside_stray.txt"
if (cd "$wt_a/sub" && "$checker" --base "$base_ref" --worktree . --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' sub/in_sub.py) > "$tmp/subdir-oos-untracked.out" 2> "$tmp/subdir-oos-untracked.err"; then
  echo "Expected --worktree . from sub/ to catch out-of-scope untracked file outside sub/" >&2
  exit 1
fi
grep -q 'outside_stray.txt' "$tmp/subdir-oos-untracked.err"
rm -f "$wt_a/outside_stray.txt"

echo "# edited outside sub" >> "$wt_a/src/b.py"
if (cd "$wt_a/sub" && "$checker" --base "$base_ref" --worktree . --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' sub/in_sub.py) > "$tmp/subdir-oos-edit.out" 2> "$tmp/subdir-oos-edit.err"; then
  echo "Expected --worktree . from sub/ to catch out-of-scope edit outside sub/" >&2
  exit 1
fi
grep -q 'src/b.py' "$tmp/subdir-oos-edit.err"
git -C "$wt_a" checkout -- src/b.py
rm -rf "$wt_a/sub"

# Commit stream A and verify committed diff mode.
git -C "$wt_a" add -A
git -C "$wt_a" commit -q -m "feat(a): increment by one"
"$checker" --base "$base_ref" --head wt/stream-a --repo "$repo" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' > "$tmp/stream-a-committed"
grep -q 'OWNERSHIP PASS: 4 path(s) verified' "$tmp/stream-a-committed"

# Stream B: implement in isolated worktree and verify ownership before landing.
cat > "$wt_b/src/b.py" <<'EOF'
def shout(text: str) -> str:
    return text.upper()
EOF
cat > "$wt_b/tests/test_b.py" <<'EOF'
import unittest
from src.b import shout


class TestB(unittest.TestCase):
    def test_shout(self):
        self.assertEqual(shout("ok"), "OK")
EOF
"$checker" --base "$base_ref" --worktree "$wt_b" --require-changes -- \
  src/b.py tests/test_b.py > "$tmp/stream-b-wt"
grep -q 'OWNERSHIP PASS: 2 path(s) verified' "$tmp/stream-b-wt"

git -C "$wt_b" add -A
git -C "$wt_b" commit -q -m "feat(b): uppercase shout"
"$checker" --base "$base_ref" --head wt/stream-b --repo "$repo" --require-changes -- \
  src/b.py tests/test_b.py > "$tmp/stream-b-committed"
grep -q 'OWNERSHIP PASS: 2 path(s) verified' "$tmp/stream-b-committed"

# Land both verified streams onto dedicated integration/task branch (main stays unchanged).
git -C "$repo" checkout -q -b integration/task "$base_ref"
git -C "$repo" merge -q --no-ff --no-edit wt/stream-a
git -C "$repo" merge -q --no-ff --no-edit wt/stream-b

[[ "$(git -C "$repo" rev-parse main)" == "$base_ref" ]]

"$checker" --base "$base_ref" --head integration/task --repo "$repo" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' src/b.py tests/test_b.py > "$tmp/integrated-own"
grep -q 'OWNERSHIP PASS: 6 path(s) verified' "$tmp/integrated-own"

# Run combined integration check after landing.
(cd "$repo" && python3 -m unittest discover -s tests -p 'test_*.py' -v) > "$tmp/unittest.out" 2>&1
grep -q 'Ran 4 tests' "$tmp/unittest.out"
grep -q '^OK$' "$tmp/unittest.out"

# --worktree must reject .git directories and bare repositories (exit 2, never OWNERSHIP PASS); --head works on bare repos.
rc=0
"$checker" --base "$base_ref" --worktree "$repo/.git" -- 'src/' > "$tmp/dotgit-wt.out" 2> "$tmp/dotgit-wt.err" || rc=$?
if (( rc != 2 )); then
  echo "Expected --worktree on .git dir to fail with exit 2, got $rc" >&2
  exit 1
fi
! grep -q 'OWNERSHIP PASS' "$tmp/dotgit-wt.out"

bare_repo="$tmp/bare.git"
git clone -q --bare "$repo" "$bare_repo"
rc=0
"$checker" --base "$base_ref" --worktree "$bare_repo" -- 'src/' > "$tmp/bare-wt.out" 2> "$tmp/bare-wt.err" || rc=$?
if (( rc != 2 )); then
  echo "Expected --worktree on bare repo to fail with exit 2, got $rc" >&2
  exit 1
fi
! grep -q 'OWNERSHIP PASS' "$tmp/bare-wt.out"

"$checker" --base "$base_ref" --head wt/stream-a --repo "$bare_repo" --require-changes -- \
  src/a.py src/a_helper.py 'tests/test_a*.py' > "$tmp/bare-head.out"
grep -q 'OWNERSHIP PASS: 4 path(s) verified' "$tmp/bare-head.out"

echo 'workstream E2E PASS: isolated worktrees, ownership gate, out-of-scope blocking, integration branch, combined tests'
