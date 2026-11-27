#!/usr/bin/env bash
# Deterministic checks for v2 graph ready, invalidate, and join.
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/skills/verification/scripts/check-graph.sh"
[[ -x "$checker" ]] || { echo "Missing executable checker: $checker" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  echo "graph-e2e FAIL: $*" >&2
  if [[ -f "$tmp/out" ]]; then
    echo "stdout:" >&2
    cat "$tmp/out" >&2
  fi
  if [[ -f "$tmp/err" ]]; then
    echo "stderr:" >&2
    cat "$tmp/err" >&2
  fi
  exit 1
}

run_check() {
  local want_rc="$1"
  local want="$2"
  shift 2
  local rc=0
  "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  if (( rc != want_rc )); then
    fail "expected exit $want_rc, got $rc for: $*"
  fi
  if [[ -n "$want" ]] && ! grep -F -q -- "$want" "$tmp/out" "$tmp/err"; then
    fail "missing [$want] for: $*"
  fi
  if (( want_rc != 0 )) && grep -F -q ' PASS' "$tmp/out"; then
    fail "unexpected PASS for: $*"
  fi
}

new_repo() {
  local dir="$1"
  mkdir -p "$dir/src"
  git -C "$dir" init -q
  git -C "$dir" config user.name "Albert Test"
  git -C "$dir" config user.email "albert-test@example.com"
  git -C "$dir" checkout -b main -q
  printf 'base\n' > "$dir/src/a.py"
  printf 'base\n' > "$dir/src/b.py"
  printf 'other\n' > "$dir/src/other.py"
  printf 'old\n' > "$dir/src/old.py"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "baseline"
}

repo="$tmp/repo"
new_repo "$repo"
base="$(git -C "$repo" rev-parse HEAD)"
short="${base:0:7}"

spec="$tmp/spec.txt"

# ready: disjoint writes pass, including a sibling prefix that must not collide.
cat > "$spec" <<EOF
id: a
write: src/

id: b
write: src2/a.py
read: docs/**
EOF
run_check 0 "GRAPH READY PASS" "$checker" ready --repo "$repo" "$spec"

# Directory prefix conflicts with a file under it.
cat > "$spec" <<EOF
id: a
write: src/

id: b
write: src/a.py
EOF
run_check 1 "write/write overlap" "$checker" ready --repo "$repo" "$spec"

# Two writers of one exact path, including a repeated write key.
cat > "$spec" <<EOF
id: a
write: docs/a.md
write: src/a.py

id: b
write: src/a.py
EOF
run_check 1 "write/write overlap" "$checker" ready --repo "$repo" "$spec"

# Read of another stream's write without a dependency.
cat > "$spec" <<EOF
id: a
write: src/a.py

id: b
read: src/*.py
EOF
run_check 1 "read/write overlap without dependency" "$checker" ready --repo "$repo" "$spec"

# Same read is allowed when the reader depends on the writer and the sha resolves.
cat > "$spec" <<EOF
id: a
write: src/a.py
status: PASS
ref: main@${short}
worktree: ${repo}

id: b
read: src/*.py
depends: a
EOF
run_check 0 "GRAPH READY PASS" "$checker" ready --repo "$repo" "$spec"

# Unknown dependency.
cat > "$spec" <<EOF
id: a
depends: missing
EOF
run_check 1 "unknown dependency" "$checker" ready --repo "$repo" "$spec"

# Missing status is not a pass. Explicit non-PASS is not a pass.
cat > "$spec" <<EOF
id: a
write: src/a.py
ref: main@${base}

id: b
depends: a
EOF
run_check 1 "dependency not PASS" "$checker" ready --repo "$repo" "$spec"

cat > "$spec" <<EOF
id: a
write: src/a.py
status: FAIL
ref: main@${base}

id: b
depends: a
EOF
run_check 1 "dependency not PASS" "$checker" ready --repo "$repo" "$spec"

# PASS with a sha that does not resolve.
cat > "$spec" <<EOF
id: a
status: PASS
ref: main@0123456789abcdef

id: b
depends: a
EOF
run_check 1 "does not resolve" "$checker" ready --repo "$repo" "$spec"

# Dependency cycle.
cat > "$spec" <<EOF
id: a
depends: b
status: PASS
ref: main@${base}

id: b
depends: a
status: PASS
ref: main@${base}
EOF
run_check 1 "cycle:" "$checker" ready --repo "$repo" "$spec"

# Mutual read/write cycle. Each read is locally depended, and the edges cycle.
cat > "$spec" <<EOF
id: a
write: src/a.py
read: src/b.py
depends: b
status: PASS
ref: main@${base}

id: b
write: src/b.py
read: src/a.py
depends: a
status: PASS
ref: main@${base}
EOF
run_check 1 "cycle:" "$checker" ready --repo "$repo" "$spec"

# Segment-bounded globs must not false-conflict.
cat > "$spec" <<EOF
id: a
write: src/*.py

id: b
write: src/nested/a.py
EOF
run_check 0 "GRAPH READY PASS" "$checker" ready --repo "$repo" "$spec"

# A dependency ref binds in its worktree. --repo and cwd are not a fallback.
other="$tmp/other-repo"
new_repo "$other"
printf 'only-other\n' > "$other/src/a.py"
git -C "$other" add src/a.py
git -C "$other" commit -q -m "only other"
other_sha="$(git -C "$other" rev-parse HEAD)"
cat > "$spec" <<EOF
id: dep-foreign
status: PASS
ref: feature@${other_sha}

id: reader
depends: dep-foreign
EOF
(
  cd "$other"
  run_check 1 "dependency ref does not resolve: dep-foreign" "$checker" ready "$spec"
)
run_check 1 "dependency ref does not resolve: dep-foreign" "$checker" ready --repo "$other" "$spec"

# Object existence does not make a branch name true.
cat > "$spec" <<EOF
id: dep-alias
status: PASS
ref: not-a-branch@${base}
worktree: ${repo}

id: reader
depends: dep-alias
EOF
run_check 1 "dependency ref mismatch: dep-alias" "$checker" ready --repo "$repo" "$spec"

cat > "$spec" <<EOF
id: dep-alias
status: PASS
ref: not-a-branch@${base}

id: reader
depends: dep-alias
EOF
run_check 1 "dependency ref does not resolve: dep-alias" "$checker" ready --repo "$repo" "$spec"

move_repo="$tmp/move-repo"
new_repo "$move_repo"
old_sha="$(git -C "$move_repo" rev-parse HEAD)"
printf 'moved\n' > "$move_repo/src/a.py"
git -C "$move_repo" add src/a.py
git -C "$move_repo" commit -q -m "move main"
cat > "$spec" <<EOF
id: dep-slipped
status: PASS
ref: main@${old_sha}
worktree: ${move_repo}

id: reader
depends: dep-slipped
EOF
run_check 1 "dependency ref mismatch: dep-slipped" "$checker" ready --repo "$move_repo" "$spec"

cat > "$spec" <<EOF
id: dep-slipped
status: PASS
ref: main@${old_sha}

id: reader
depends: dep-slipped
EOF
run_check 1 "dependency ref does not resolve: dep-slipped" "$checker" ready --repo "$move_repo" "$spec"

# invalidate fixtures: upstream and reader worktrees.
wt_up="$tmp/wt-up"
wt_reader="$tmp/wt-reader"
git -C "$repo" worktree add -q -b wt/up "$wt_up" "$base"
git -C "$repo" worktree add -q -b wt/reader "$wt_reader" "$base"
reader_sha="$(git -C "$wt_reader" rev-parse HEAD)"

# Non-overlapping upstream edit does not invalidate.
printf 'changed\n' > "$wt_up/src/other.py"
git -C "$wt_up" add src/other.py
git -C "$wt_up" commit -q -m "edit other"
up_other="$(git -C "$wt_up" rev-parse HEAD)"

cat > "$spec" <<EOF
id: up
write: src/other.py
status: PASS
ref: wt/up@${up_other}
worktree: ${wt_up}

id: reader
read: src/a.py
status: PASS
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${base}
EOF
spec_sum="$(sha256sum "$spec" | awk '{print $1}')"
run_check 0 "GRAPH INVALIDATE PASS" "$checker" invalidate "$spec"
[[ "$(sha256sum "$spec" | awk '{print $1}')" == "$spec_sum" ]] || fail "invalidate rewrote the spec"
[[ -z "$(git -C "$wt_up" status --porcelain --untracked-files=all)" ]] || fail "invalidate dirtied upstream"
[[ -z "$(git -C "$wt_reader" status --porcelain --untracked-files=all)" ]] || fail "invalidate dirtied reader"

# Ignored files are not dirty under the required status command.
printf '*.log\n' >> "$wt_up/.gitignore"
git -C "$wt_up" add .gitignore
git -C "$wt_up" commit -q -m "ignore logs"
up_ignore="$(git -C "$wt_up" rev-parse HEAD)"
printf 'noise\n' > "$wt_up/noise.log"
cat > "$spec" <<EOF
id: up
ref: wt/up@${up_ignore}
worktree: ${wt_up}

id: reader
read: src/a.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${up_other}
EOF
run_check 0 "GRAPH INVALIDATE PASS" "$checker" invalidate "$spec"
rm -f -- "$wt_up/noise.log"

# Dirty worktree, including an untracked file, fails closed.
mkdir -p "$wt_reader/notes"
printf 'stray\n' > "$wt_reader/notes/a.txt"
cat > "$spec" <<EOF
id: up
ref: wt/up@${up_ignore}
worktree: ${wt_up}

id: reader
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "dirty worktree" "$checker" invalidate "$spec"
rm -rf -- "$wt_reader/notes"

# Ref mismatch: HEAD moved, spec still names the old sha.
cat > "$spec" <<EOF
id: up
ref: wt/up@${base}
worktree: ${wt_up}

id: reader
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "ref mismatch" "$checker" invalidate "$spec"

# Branch mismatch with the right commit.
git -C "$wt_reader" checkout -q -b wt/wrong "$reader_sha"
cat > "$spec" <<EOF
id: reader
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "ref mismatch" "$checker" invalidate "$spec"
git -C "$wt_reader" checkout -q wt/reader

# Missing old sha is stale. Spec is not rewritten.
cat > "$spec" <<EOF
id: up
ref: wt/up@${up_ignore}
worktree: ${wt_up}

id: reader
read: src/a.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@0123456789abcdef
EOF
spec_sum="$(sha256sum "$spec" | awk '{print $1}')"
run_check 1 "missing sha" "$checker" invalidate "$spec"
[[ "$(sha256sum "$spec" | awk '{print $1}')" == "$spec_sum" ]] || fail "stale invalidate rewrote the spec"

# Upstream rename: either path intersecting a declared read is stale.
printf 'same\n' > "$wt_up/src/old.py"
git -C "$wt_up" add src/old.py
git -C "$wt_up" commit -q -m "snapshot old"
pre_rename="$(git -C "$wt_up" rev-parse HEAD)"
git -C "$wt_up" mv "src/old.py" "src/new.py"
git -C "$wt_up" commit -q -m "rename old"
post_rename="$(git -C "$wt_up" rev-parse HEAD)"

cat > "$spec" <<EOF
id: up
ref: wt/up@${post_rename}
worktree: ${wt_up}

id: reader
read: src/old.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_rename}
EOF
run_check 1 "intersects read via src/old.py" "$checker" invalidate "$spec"

cat > "$spec" <<EOF
id: up
ref: wt/up@${post_rename}
worktree: ${wt_up}

id: reader
read: src/new.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_rename}
EOF
run_check 1 "intersects read via src/new.py" "$checker" invalidate "$spec"

# A rename whose paths do not intersect reads is not stale.
cat > "$spec" <<EOF
id: up
ref: wt/up@${post_rename}
worktree: ${wt_up}

id: reader
read: src/a.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_rename}
EOF
run_check 0 "GRAPH INVALIDATE PASS" "$checker" invalidate "$spec"

# Copy records are parsed on both paths. Modify the source in the same commit so -C emits both.
copy_base="$(git -C "$wt_up" rev-parse HEAD)"
printf 'copy-body\n' > "$wt_up/src/orig.py"
git -C "$wt_up" add src/orig.py
git -C "$wt_up" commit -q -m "add orig"
pre_copy="$(git -C "$wt_up" rev-parse HEAD)"
cp "$wt_up/src/orig.py" "$wt_up/src/copy.py"
printf 'copy-body\nextra\n' > "$wt_up/src/orig.py"
git -C "$wt_up" add src/orig.py src/copy.py
git -C "$wt_up" commit -q -m "copy orig"
post_copy="$(git -C "$wt_up" rev-parse HEAD)"
git -C "$wt_up" diff --name-status -z -M -C "${pre_copy}..${post_copy}" | tr '\0' '\n' > "$tmp/copy-diff.txt"
grep -q '^C' "$tmp/copy-diff.txt" || fail "fixture did not produce a copy record: $(cat "$tmp/copy-diff.txt")"

cat > "$spec" <<EOF
id: up
ref: wt/up@${post_copy}
worktree: ${wt_up}

id: reader
read: src/copy.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_copy}
EOF
run_check 1 "intersects read via src/copy.py" "$checker" invalidate "$spec"

cat > "$spec" <<EOF
id: up
ref: wt/up@${post_copy}
worktree: ${wt_up}

id: reader
read: src/orig.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_copy}
EOF
run_check 1 "intersects read via src/orig.py" "$checker" invalidate "$spec"

# Space in a renamed path must survive NUL parsing.
git -C "$wt_up" checkout -q -B wt/up "$copy_base"
printf 'spaced\n' > "$wt_up/src/my file.py"
git -C "$wt_up" add "src/my file.py"
git -C "$wt_up" commit -q -m "add spaced"
pre_space="$(git -C "$wt_up" rev-parse HEAD)"
git -C "$wt_up" mv "src/my file.py" "src/other file.py"
git -C "$wt_up" commit -q -m "rename spaced"
post_space="$(git -C "$wt_up" rev-parse HEAD)"
cat > "$spec" <<EOF
id: up
ref: wt/up@${post_space}
worktree: ${wt_up}

id: reader
read: src/other file.py
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
verified_against: up@${pre_space}
EOF
run_check 1 "intersects read via src/other file.py" "$checker" invalidate "$spec"

# join: clean integration checkout bound to its ref, inputs PASS and resolvable.
git -C "$wt_up" checkout -q wt/up
up_join="$(git -C "$wt_up" rev-parse HEAD)"
int_wt="$tmp/wt-int"
git -C "$repo" worktree add -q -b integration/task "$int_wt" "$base"
int_sha="$(git -C "$int_wt" rev-parse HEAD)"

cat > "$spec" <<EOF
id: up
status: PASS
ref: wt/up@${up_join}
worktree: ${wt_up}

id: reader
status: PASS
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 0 "GRAPH JOIN PASS" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

# Short integration sha still binds when it resolves to HEAD.
run_check 0 "GRAPH JOIN PASS" \
  "$checker" join --integration-ref "integration/task@${int_sha:0:7}" --integration-worktree "$int_wt" "$spec"

# Missing integration binding is usage failure, not a pass.
run_check 2 "integration-ref" "$checker" join --integration-worktree "$int_wt" "$spec"
run_check 2 "integration-worktree" "$checker" join --integration-ref "integration/task@${int_sha}" "$spec"

# Integration checkout stale or dirty.
printf 'int\n' > "$int_wt/src/a.py"
git -C "$int_wt" add src/a.py
git -C "$int_wt" commit -q -m "integration move"
cat > "$spec" <<EOF
id: reader
status: PASS
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "integration ref mismatch" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

git -C "$int_wt" reset -q --hard "$int_sha"
printf 'dirty\n' > "$int_wt/stray.txt"
run_check 1 "integration dirty" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"
rm -f -- "$int_wt/stray.txt"

# Input not PASS, unresolvable ref, and stale worktree HEAD.
cat > "$spec" <<EOF
id: reader
status: FAIL
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "input not PASS" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

cat > "$spec" <<EOF
id: reader
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "input not PASS" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

cat > "$spec" <<EOF
id: reader
status: PASS
ref: wt/reader@0123456789abcdef
worktree: ${wt_reader}
EOF
run_check 1 "input ref does not resolve" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

printf 'reader move\n' > "$wt_reader/src/a.py"
git -C "$wt_reader" add src/a.py
git -C "$wt_reader" commit -q -m "reader move"
cat > "$spec" <<EOF
id: reader
status: PASS
ref: wt/reader@${reader_sha}
worktree: ${wt_reader}
EOF
run_check 1 "input ref stale" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"
git -C "$wt_reader" reset -q --hard "$reader_sha"

printf 'dirty reader\n' > "$wt_reader/dirty.txt"
run_check 1 "input dirty" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"
rm -f -- "$wt_reader/dirty.txt"

# An object in the integration repo is not an input binding.
cat > "$spec" <<EOF
id: join-ghost
status: PASS
ref: not-a-branch@${int_sha}
EOF
run_check 1 "input ref does not resolve: join-ghost" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

cat > "$spec" <<EOF
id: join-unbound
status: PASS
ref: integration/task@${int_sha}
EOF
run_check 1 "input ref does not resolve: join-unbound" \
  "$checker" join --integration-ref "integration/task@${int_sha}" --integration-worktree "$int_wt" "$spec"

echo "graph E2E PASS: ready cycles and overlaps, invalidate staleness, join bindings"
