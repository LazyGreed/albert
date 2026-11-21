#!/usr/bin/env bash
# Opt-in live native-harness smoke test (NOT run in .github/workflows/ci.yml).
#
# Prerequisites:
#   - Authenticated `agy` CLI (default) or `claude` CLI on PATH
#   - `git` and `python3` available
#
# Usage:
#   bash tests/live-parallel-smoke.sh
#   ALBERT_SMOKE_HARNESS=claude bash tests/live-parallel-smoke.sh
#   ALBERT_SMOKE_KEEP_TMP=1 bash tests/live-parallel-smoke.sh
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
harness="${ALBERT_SMOKE_HARNESS:-agy}"

case "$harness" in
  agy)
    install_harness="antigravity"
    check_script=".agents/skills/verification/scripts/check-ownership.sh"
    ;;
  claude)
    install_harness="claude"
    check_script=".claude/skills/verification/scripts/check-ownership.sh"
    ;;
  *)
    echo "Unsupported ALBERT_SMOKE_HARNESS: $harness (expected agy or claude)" >&2
    exit 2
    ;;
esac

command -v "$harness" >/dev/null 2>&1 || {
  echo "Required harness CLI not found on PATH: $harness" >&2
  exit 1
}

tmp="$(mktemp -d -t albert-live-smoke-XXXXXX)"
cleanup() {
  if [[ "${ALBERT_SMOKE_KEEP_TMP:-0}" == "1" ]]; then
    echo "Kept temp dir: $tmp"
  else
    rm -rf -- "$tmp"
  fi
}
trap cleanup EXIT

repo="$tmp/repo"
mkdir -p "$repo/src" "$repo/tests"

git -C "$repo" init -q
git -C "$repo" config user.name "Albert Smoke"
git -C "$repo" config user.email "albert-smoke@example.com"
git -C "$repo" checkout -b main -q

cat > "$repo/.gitignore" <<'EOF'
__pycache__/
*.pyc
.pytest_cache/
EOF

cat > "$repo/src/__init__.py" <<'EOF'
EOF

cat > "$repo/src/math.py" <<'EOF'
def add(a: int, b: int) -> int:
    """Return a + b."""
    raise NotImplementedError


def mul(a: int, b: int) -> int:
    """Return a * b."""
    raise NotImplementedError
EOF

cat > "$repo/src/text.py" <<'EOF'
def slugify(text: str) -> str:
    """Lowercase text, strip edges, and collapse spaces/underscores/hyphens into single hyphens."""
    raise NotImplementedError


def shout(text: str) -> str:
    """Uppercase text and append '!' if it does not already end with '!'."""
    raise NotImplementedError
EOF

cat > "$repo/tests/test_math.py" <<'EOF'
import unittest
from src.math import add, mul


class TestMath(unittest.TestCase):
    def test_placeholder(self):
        self.assertEqual(add(1, 2), 3)
        self.assertEqual(mul(2, 3), 6)


if __name__ == "__main__":
    unittest.main()
EOF

cat > "$repo/tests/test_text.py" <<'EOF'
import unittest
from src.text import shout, slugify


class TestText(unittest.TestCase):
    def test_placeholder(self):
        self.assertEqual(slugify("Hello World"), "hello-world")
        self.assertEqual(shout("hi"), "HI!")


if __name__ == "__main__":
    unittest.main()
EOF

cat > "$repo/tests/test_all.py" <<'EOF'
import unittest
from src.math import add, mul
from src.text import shout, slugify


class TestAll(unittest.TestCase):
    def test_math_and_text_integration(self):
        label = slugify("Build Status_OK")
        total = add(2, mul(3, 4))
        self.assertEqual(label, "build-status-ok")
        self.assertEqual(total, 14)
        self.assertEqual(shout(f"{label} {total}"), "BUILD-STATUS-OK 14!")


if __name__ == "__main__":
    unittest.main()
EOF

"$root/install.sh" --harness "$install_harness" --scope project --target "$repo" --no-tui >/dev/null

git -C "$repo" add -A
git -C "$repo" commit -q -m "chore: baseline project with albert installed"
base_ref="$(git -C "$repo" rev-parse HEAD)"

prompt="$(cat <<EOF
Coordinate two parallel Felix implementation streams in isolated git worktrees from base commit $base_ref, verify each stream before landing, and run the combined check.

Requirements:
1. Create two isolated git worktrees from $base_ref:
   - ../wt-math on branch wt/math
   - ../wt-text on branch wt/text
2. Dispatch two parallel Felix instances with exclusive ownership:
   - felix-math (STREAM: math, WRITE OWNERSHIP: src/math.py, tests/test_math.py, DO NOT EDIT: src/text.py, tests/test_text.py, tests/test_all.py): implement add and mul in src/math.py and real unit tests in tests/test_math.py; commit on wt/math.
   - felix-text (STREAM: text, WRITE OWNERSHIP: src/text.py, tests/test_text.py, DO NOT EDIT: src/math.py, tests/test_math.py, tests/test_all.py): implement slugify and shout in src/text.py and real unit tests in tests/test_text.py; commit on wt/text.
3. Before landing onto integration/task:
   - Mechanically verify each stream's ownership with:
     $check_script --base $base_ref --head wt/math --repo . --require-changes -- src/math.py tests/test_math.py
     $check_script --base $base_ref --head wt/text --repo . --require-changes -- src/text.py tests/test_text.py
   - Obtain two separate read-only Vera verdicts (STREAM math and STREAM text), requiring VERDICT PASS for each.
4. Land both verified branches (wt/math and wt/text) onto a dedicated task integration branch named integration/task (created from $base_ref). Do NOT merge into main.
5. On integration/task, run the combined integration check:
   python3 -m unittest tests/test_math.py tests/test_text.py tests/test_all.py -v
6. Report both Vera verdicts, ownership check outputs, integration/task ref, and test results.
EOF
)"

log_file="$tmp/harness.log"
echo "Running live smoke test with harness=$harness in $repo (base=$base_ref)..."

(
  cd "$repo"
  if [[ "$harness" == "agy" ]]; then
    agy_args=(--dangerously-skip-permissions "--print=$prompt")
    if [[ -n "${ALBERT_SMOKE_TIMEOUT:-}" ]]; then
      agy_args+=("--print-timeout=$ALBERT_SMOKE_TIMEOUT")
    fi
    agy "${agy_args[@]}"
  else
    claude --print --dangerously-skip-permissions "$prompt"
  fi
) 2>&1 | tee "$log_file"

# Verify main was not mutated and integration/task exists.
[[ "$(git -C "$repo" rev-parse main)" == "$base_ref" ]] || {
  echo "FAIL: main branch was modified" >&2
  exit 1
}

git -C "$repo" rev-parse --verify integration/task >/dev/null 2>&1 || {
  echo "FAIL: integration/task branch was not created" >&2
  exit 1
}

# Verify mechanical ownership of the combined diff on integration/task.
"$repo/$check_script" --base "$base_ref" --head integration/task --repo "$repo" --require-changes -- \
  src/math.py tests/test_math.py src/text.py tests/test_text.py

diff_files="$(git -C "$repo" diff --name-only "$base_ref..integration/task")"
for expected in src/math.py tests/test_math.py src/text.py tests/test_text.py; do
  grep -Fxq "$expected" <<< "$diff_files" || {
    echo "FAIL: expected $expected in integration/task diff, got:" >&2
    printf '%s\n' "$diff_files" >&2
    exit 1
  }
done

# Verify combined tests pass on integration/task.
git -C "$repo" checkout -q integration/task
(cd "$repo" && python3 -m unittest tests/test_math.py tests/test_text.py tests/test_all.py -v)

# Verify harness output reflects Vera verdicts and integration gate.
grep -qi 'PASS' "$log_file" || {
  echo "FAIL: harness log missing PASS verdict" >&2
  exit 1
}
grep -q 'integration/task' "$log_file" || {
  echo "FAIL: harness log missing integration/task reference" >&2
  exit 1
}

echo "LIVE PARALLEL SMOKE PASS ($harness): ownership verified, Vera verdicts logged, integration/task tests pass"
