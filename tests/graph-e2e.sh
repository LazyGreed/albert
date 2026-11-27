#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/skills/verification/scripts/check-graph.sh"
readonly_checker="$root/skills/verification/scripts/check-readonly.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

fail() {
  printf 'graph-e2e FAIL: %s\n' "$*" >&2
  cat "$tmp/out" "$tmp/err" >&2
  exit 1
}

run_check() {
  local want_rc="$1" want="$2" rc=0
  shift 2
  "$@" > "$tmp/out" 2> "$tmp/err" || rc=$?
  (( rc == want_rc )) || fail "expected exit $want_rc, got $rc for $*"
  grep -Fq -- "$want" "$tmp/out" "$tmp/err" || fail "missing [$want] for $*"
  if (( want_rc != 0 )) && grep -Eq '^GRAPH .* PASS$' "$tmp/out"; then
    fail "unexpected gate PASS for $*"
  fi
}

new_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name 'Quintet Graph Tests'
  git -C "$1" config user.email 'graph@example.com'
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
  git -C "$1" rev-parse HEAD
}

repo="$tmp/repo"
new_repo "$repo"
mkdir -p "$repo/shared"
printf 'path content used for rename and copy checks\n' > "$repo/shared/read.txt"
printf 'literal read\n' > "$repo/shared/owned\."
printf 'neighbor\n' > "$repo/shared/owned\X"
hidden_path=$'shared/with\nnewline'
printf 'hidden\n' > "$repo/$hidden_path"
printf 'target commit\n' > "$repo/README"
initial="$(commit_all "$repo" baseline)"
printf 'advance target\n' >> "$repo/README"
base="$(commit_all "$repo" 'advance target')"
base_ref="main@${base:0:7}"
plan="$tmp/plan"
evidence="$tmp/evidence"

write_plan() {
  local read_path="${1:-shared/read.txt}"
  cat > "$plan" <<EOF
id: leaf
write: leaf/
depends: reader

id: reader
write: reader/**
read: $read_path
read_depends: up

id: up
write: shared/**
write: up/
EOF
}

stream_record() {
  local id="$1" ref="$2" worktree="$3" verdict_ref="$4" verdict_base="$5"
  shift 5
  printf 'id: %s\nstatus: PASS\nref: %s\nworktree: %s\n' "$id" "$ref" "$worktree"
  if [[ -n "$verdict_ref" ]]; then printf 'verdict_ref: %s\n' "$verdict_ref"; fi
  if [[ -n "$verdict_base" ]]; then printf 'verdict_base: %s\n' "$verdict_base"; fi
  if (( $# )); then printf 'verified_against: %s\n' "$@"; fi
  printf '\n'
}

pass_record() {
  local id="$1" ref="$2" worktree="$3"
  shift 3
  stream_record "$id" "$ref" "$worktree" "$ref" "$base" "$@"
}

check() {
  local stage="$1"
  shift
  "$checker" "$stage" --plan "$plan" --base-ref "$base_ref" --repo "$repo" "$@" "$evidence"
}

write_plan
: > "$evidence"
run_check 0 'GRAPH READY PASS' check ready --stream up
run_check 1 'stream not PASS: up' check ready --stream reader
run_check 1 'stream not PASS: reader' check ready --stream leaf
run_check 2 '--plan is required' "$checker" ready --base-ref "$base_ref" "$evidence"
run_check 2 '--base-ref is required' "$checker" ready --plan "$plan" "$evidence"
run_check 2 'unknown --stream' check ready --stream ghost
run_check 2 'plan and evidence must be separate files' "$checker" ready --plan "$plan" --base-ref "$base_ref" "$plan"
printf 'id: up\nstatus: P\0ASS\n' > "$evidence"
run_check 2 'NUL byte in evidence file' check ready --stream up

up="$tmp/wt up"
reader="$tmp/wt-reader"
leaf="$tmp/wt-leaf"
int="$tmp/wt-int"
git -C "$repo" worktree add -qb wt/up "$up" "$base"
git -C "$repo" worktree add -qb wt/reader "$reader" "$base"
git -C "$repo" worktree add -qb wt/leaf "$leaf" "$base"
git -C "$repo" worktree add -qb integration/task "$int" "$base"
mkdir -p "$up/up" "$reader/reader" "$leaf/leaf"
printf 'first upstream patch\n' > "$up/up/result"
printf 'reader patch\n' > "$reader/reader/result"
printf 'leaf patch\n' > "$leaf/leaf/result"
old_up="$(commit_all "$up" 'first upstream patch')"
reader_head="$(commit_all "$reader" 'reader patch')"
leaf_head="$(commit_all "$leaf" 'leaf patch')"
reader_ref="wt/reader@$reader_head"
leaf_ref="wt/leaf@$leaf_head"
up_head="$old_up"
up_ref="wt/up@$up_head"
read_ref="$up_ref"

write_evidence() {
  {
    pass_record leaf "$leaf_ref" "$leaf" "reader=$reader_ref"
    pass_record up "$up_ref" "$up"
    pass_record reader "$reader_ref" "$reader" "up=$read_ref"
  } > "$evidence"
}

pass_record up "$up_ref" "$up" > "$evidence"
run_check 0 'GRAPH READY PASS' check ready --stream reader
run_check 0 'GRAPH INVALIDATE PASS' check invalidate --stream up
run_check 1 'stream not PASS: reader' check ready --stream leaf
printf 'id: up\nstatus: PASS\nref: %s\n' "$up_ref" > "$evidence"
run_check 1 'worktree unavailable' check ready --stream reader
stream_record up "$up_ref" "$up" '' '' > "$evidence"
run_check 1 'stream up verdict REF mismatch' check ready --stream reader
run_check 1 'stream up verdict BASE mismatch' check ready --stream reader
stream_record up "$up_ref" "$up" "wrong@$up_head" "$base" > "$evidence"
run_check 1 'stream up verdict REF mismatch' check ready --stream reader
stream_record up "$up_ref" "$up" "$up_ref" "$up_head" > "$evidence"
run_check 1 'stream up verdict BASE mismatch' check ready --stream reader
pass_record up "$up_ref" "$up/up" > "$evidence"
run_check 1 'not a worktree root' check ready --stream reader
pass_record up "$up_ref" "$up" > "$evidence"
printf 'untracked\n' > "$up/stray"
run_check 1 'stream up dirty worktree' check ready --stream reader
rm -- "$up/stray"
if [[ ! -e "$up/readme" ]]; then
  git -C "$up" config core.ignoreCase true
  printf 'untracked case variant\n' > "$up/readme"
  run_check 1 'stream up dirty worktree' check ready --stream reader
  rm -- "$up/readme"
  git -C "$up" config --unset core.ignoreCase
fi
git -C "$up" config core.filemode false
chmod +x "$up/up/result"
run_check 1 'stream up dirty worktree' check ready --stream reader
chmod -x "$up/up/result"
git -C "$up" config --unset core.filemode
git -C "$up" update-index --assume-unchanged -- "$hidden_path"
printf 'edit hidden from status\n' > "$up/$hidden_path"
[[ -z "$(git -C "$up" status --porcelain --untracked-files=all)" ]] || fail 'assume-unchanged fixture is visible'
run_check 1 'hidden index path' check ready --stream reader
git -C "$up" update-index --no-assume-unchanged -- "$hidden_path"
git -C "$up" restore -- "$hidden_path"
git -C "$up" update-index --skip-worktree -- shared/read.txt
run_check 1 'skip-worktree' check invalidate --stream up
git -C "$up" update-index --no-skip-worktree -- shared/read.txt

# A foreign worktree with the same commit cannot supply a prerequisite.
foreign="$tmp/foreign"
git clone -q --no-local "$repo" "$foreign"
pass_record up "main@$base" "$foreign" > "$evidence"
run_check 1 'worktree repository differs' check ready --stream reader

write_evidence
run_check 0 'GRAPH READY PASS' check ready --stream leaf
run_check 0 'GRAPH INVALIDATE PASS' check invalidate
run_check 0 'GRAPH INVALIDATE PASS' "$checker" invalidate --plan "$plan" --base-ref "$base_ref" "$evidence"
run_check 1 'base branch unavailable' "$checker" invalidate --plan "$plan" --base-ref "missing@$base" "$evidence"
git -C "$repo" branch moved "$old_up"
run_check 1 'base ref stale' "$checker" invalidate --plan "$plan" --base-ref "moved@$base" "$evidence"

# Plan rules apply across all phases and even outside the selected subgraph.
integration_head="$base"
join() {
  check join --integration-ref "integration/task@${integration_head:0:7}" --integration-worktree "$int" "$@"
}

for stage in ready invalidate join; do
  if [[ "$stage" == join ]]; then cmd=(join); else cmd=(check "$stage" --stream up); fi
  write_plan
  printf 'write: ./up/**\n' >> "$plan"
  run_check 2 'duplicate plan attribute: write:up/**' "${cmd[@]}"
  write_plan
  printf 'depends: unknown\n' >> "$plan"
  run_check 1 'unknown depends edge' "${cmd[@]}"
  write_plan
  printf 'depends: leaf\n' >> "$plan"
  run_check 1 'cycle:' "${cmd[@]}"
  write_plan
  printf 'write: reader/result\n' >> "$plan"
  run_check 1 'write/write overlap' "${cmd[@]}"
  write_plan
  printf 'read: leaf/**/result\n' >> "$plan"
  run_check 1 'read/write overlap without dependency' "${cmd[@]}"
  cat > "$plan" <<'EOF'
id: up
write: shared/*.txt

id: reader
write: shared/nested/a.txt
read: shared/read.txt
EOF
  run_check 1 'read/write overlap without dependency' "${cmd[@]}"
  printf 'depends: up\nread_depends: up\n' >> "$plan"
  run_check 1 'edge declared as hard and read-only' "${cmd[@]}"
  cat > "$plan" <<'EOF'
id: up
write: shared/*.txt

id: reader
write: shared/nested/a.txt
EOF
  # Incorrect evidence fails after graph validation, proving the glob pair is disjoint.
  run_check 2 'evidence for unplanned stream: leaf' "${cmd[@]}"
done
write_plan

# Upstream movement keeps the read-only verdict when narrow reads are unaffected.
printf 'non-overlapping edit\n' >> "$up/up/result"
up_head="$(commit_all "$up" 'edit outside reader paths')"
run_check 1 'stream up ref mismatch' check ready --stream reader
run_check 1 'stream up ref mismatch' check invalidate
up_ref="wt/up@$up_head"
write_evidence
run_check 0 'GRAPH READY PASS' check ready --stream leaf
run_check 0 'GRAPH INVALIDATE PASS' check invalidate
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader"
  pass_record leaf "$leaf_ref" "$leaf" "reader=$reader_ref"
} > "$evidence"
run_check 1 'missing verified_against: reader -> up (read_depends)' check invalidate
run_check 1 'missing verified_against: reader -> up (read_depends)' check ready --stream leaf
write_evidence
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$read_ref" "up=$up_ref"
} > "$evidence"
run_check 2 'duplicate input ref: reader -> up' check invalidate
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$read_ref" "leaf=$leaf_ref"
} > "$evidence"
run_check 2 'verified_against for undeclared edge' check ready --stream up

# A same-tree commit on another branch cannot serve as a historical input.
other_commit="$(git -C "$repo" commit-tree "${up_head}^{tree}" -p "$base" -m 'parallel history')"
read_ref="wt/up@$other_commit"
write_evidence
run_check 1 'outside upstream ancestry' check invalidate
read_ref="wt/up@$initial"
write_evidence
run_check 1 'predates BASE' check invalidate
read_ref='wt/up@0123456789abcdef'
write_evidence
run_check 1 'invalid historical read ref' check invalidate
read_ref="other@$up_head"
write_evidence
run_check 1 'invalid historical read ref' check invalidate

# An unchanged copy source still counts, and paths with spaces stay intact.
cp "$up/shared/read.txt" "$up/shared/copy out.txt"
read_ref="$up_ref"
up_head="$(commit_all "$up" 'copy read source')"
up_ref="wt/up@$up_head"
write_evidence
run_check 1 'intersects read via shared/read.txt' check invalidate
run_check 1 'reader has no current PASS' check invalidate
run_check 0 'GRAPH INVALIDATE PASS' check invalidate --stream up
write_plan 'shared/copy out.txt'
run_check 1 'intersects read via shared/copy out.txt' check invalidate
write_plan
read_ref="$up_ref"
git -C "$up" mv -- shared/read.txt 'shared/renamed out.txt'
up_head="$(commit_all "$up" 'rename read source')"
up_ref="wt/up@$up_head"
write_evidence
run_check 1 'intersects read via shared/read.txt' check invalidate
write_plan 'shared/renamed out.txt'
run_check 1 'intersects read via shared/renamed out.txt' check invalidate
write_plan 'shared/unrelated.txt'
run_check 0 'GRAPH INVALIDATE PASS' check invalidate
write_plan
run_check 1 'intersects read via shared/read.txt' check ready --stream leaf
run_check 1 'reader has no current PASS' check invalidate --stream leaf

# Rechecking the reader against the current upstream restores its unchanged REF.
read_ref="$up_ref"
write_evidence
run_check 0 'GRAPH INVALIDATE PASS' check invalidate --stream leaf

# The same path syntax governs overlap checks and historical read invalidation.
write_plan 'shared/owned\.'
printf 'neighbor edit\n' >> "$up/shared/owned\X"
printf 'edit newline path\n' >> "$up/$hidden_path"
up_head="$(commit_all "$up" 'edit neighboring path with a backslash')"
up_ref="wt/up@$up_head"
write_evidence
run_check 0 'GRAPH INVALIDATE PASS' check invalidate
read_ref="$up_ref"
printf 'literal path edit\n' >> "$up/shared/owned\."
up_head="$(commit_all "$up" 'edit literal path with a backslash')"
up_ref="wt/up@$up_head"
write_evidence
run_check 1 'intersects read via shared/owned\.' check invalidate
read_ref="$up_ref"
write_plan
write_evidence

printf 'reader second patch\n' >> "$reader/reader/result"
new_reader="$(commit_all "$reader" 'move reader')"
{
  pass_record leaf "$leaf_ref" "$leaf" "reader=$reader_ref"
  pass_record up "$up_ref" "$up"
  pass_record reader "wt/reader@$new_reader" "$reader" "up=$read_ref"
} > "$evidence"
run_check 1 'does not match hard dependency' check invalidate
git -C "$reader" reset -q --hard "$reader_head"
write_evidence

# Ownership is mandatory for a fresh bound verdict, including inherited paths.
risky="$tmp/risky"
git -C "$repo" worktree add -qb wt/risky "$risky" "$up_head"
mkdir "$risky/reader"
printf 'inherited baseline\n' > "$risky/reader/result"
risky_head="$(commit_all "$risky" 'dependent with inherited changes')"
{
  pass_record up "$up_ref" "$up"
  pass_record reader "wt/risky@$risky_head" "$risky" "up=$up_ref"
} > "$evidence"
run_check 1 'stream reader ownership check failed' check invalidate --stream reader
run_check 1 'out-of-scope path' check invalidate --stream reader
run_check 1 'stream reader ownership check failed' check ready --stream leaf
pass_record up "main@$base" "$repo" > "$evidence"
run_check 1 'no changed paths found' check invalidate --stream up
run_check 1 'no changed paths found' check ready --stream reader

off_base="$tmp/off-base"
git -C "$repo" worktree add -qb wt/off-base "$off_base" "$initial"
mkdir "$off_base/up"
printf 'owned patch off the current base\n' > "$off_base/up/result"
off_head="$(commit_all "$off_base" 'edit from old base')"
pass_record up "wt/off-base@$off_head" "$off_base" > "$evidence"
run_check 1 'ownership baseline is outside stream ancestry' check ready --stream reader
run_check 1 'ownership baseline is outside stream ancestry' check invalidate --stream up

printf 'unowned history\n' > "$up/unowned"
commit_all "$up" 'add unowned path' > /dev/null
rm -- "$up/unowned"
foreign_revert="$(commit_all "$up" 'remove unowned path')"
pass_record up "wt/up@$foreign_revert" "$up" > "$evidence"
run_check 1 "stream up ownership check failed at commit $foreign_revert" check ready --stream reader
run_check 1 'out-of-scope path' check invalidate --stream up
git -C "$up" reset -q --hard "$up_head"

# Integration has its own verdict and must contain the exact planned patches.
combined_record() {
  local ref="$1" bound_base="$2" status="$3"
  shift 3
  printf 'status: %s\nintegration_ref: %s\nverdict_base: %s\n' "$status" "$ref" "$bound_base"
  if (( $# )); then printf 'input_ref: %s\n' "$@"; fi
}

write_join_evidence() {
  write_evidence
  combined_record "integration/task@$integration_head" "$base" PASS \
    "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
}

write_join_evidence
run_check 1 'input not in integration history: up' join
run_check 1 'integration branch must differ from the target branch' check join \
  --integration-ref "main@$base" --integration-worktree "$repo"
run_check 1 'integration must use a separate branch and worktree from stream up' check join \
  --integration-ref "$up_ref" --integration-worktree "$up"
git -C "$int" merge -q --no-ff -m 'land upstream' "$up_head"
git -C "$int" merge -q --no-ff -m 'land reader' "$reader_head"
pre_leaf="$(git -C "$int" rev-parse HEAD)"
integration_head="$pre_leaf"
write_join_evidence
run_check 1 'input not in integration history: leaf' join
git -C "$int" merge -q --no-ff -m 'land leaf' "$leaf_head"
integration_head="$(git -C "$int" rev-parse HEAD)"
joined="$integration_head"
write_join_evidence

for name in "$up" "$reader" "$leaf" "$int"; do
  "$readonly_checker" snapshot "$name" > "$tmp/snapshot-${name##*/}"
done
cp "$evidence" "$tmp/evidence.before"
cp "$plan" "$tmp/plan.before"
run_check 0 'GRAPH JOIN PASS' join
mkdir "$tmp/scratch"
TMPDIR="$tmp/scratch" run_check 0 'GRAPH JOIN PASS' join
[[ -z "$(ls -A "$tmp/scratch")" ]] || fail 'join left temporary files behind'
TMPDIR="$int" run_check 2 'temporary directory must be outside Git repositories' join
for name in "$up" "$reader" "$leaf" "$int"; do
  run_check 0 READONLY_OK "$readonly_checker" verify "$tmp/snapshot-${name##*/}" "$name"
done
cmp -s "$evidence" "$tmp/evidence.before" || fail 'join rewrote evidence'
cmp -s "$plan" "$tmp/plan.before" || fail 'join rewrote plan'

write_evidence
run_check 1 'combined verdict not PASS' join
combined_record "integration/task@$joined" "$base" FAIL "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
run_check 1 'combined verdict not PASS' join
write_evidence
combined_record "integration/task@$pre_leaf" "$base" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
run_check 1 'combined verdict INTEGRATION_REF mismatch' join
write_evidence
combined_record "other@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
run_check 1 'combined verdict INTEGRATION_REF mismatch' join
write_evidence
combined_record "integration/task@$joined" "$up_head" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
run_check 1 'combined verdict BASE mismatch' join
write_evidence
combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref" >> "$evidence"
run_check 1 'missing combined input_ref: leaf' join
write_evidence
combined_record "integration/task@$joined" "$base" PASS "up=wrong@$up_head" "reader=$reader_ref" "leaf=$leaf_ref" >> "$evidence"
run_check 1 'combined input_ref mismatch: up' join
write_evidence
combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "up=wt/up@$old_up" >> "$evidence"
run_check 2 'duplicate input ref: (join) -> up' join

# Integration ancestry cannot stand in for a missing or stale stream verdict.
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$up_ref"
  combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref"
} > "$evidence"
run_check 1 'stream not PASS: leaf' join
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$up_ref"
  stream_record leaf "$leaf_ref" "$leaf" '' '' "reader=$reader_ref"
  combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref"
} > "$evidence"
run_check 1 'stream leaf verdict REF mismatch' join
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$up_ref"
  pass_record leaf "$leaf_ref" "$leaf"
  combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref"
} > "$evidence"
run_check 1 'missing verified_against: leaf -> reader' join
{
  pass_record up "$up_ref" "$up"
  pass_record reader "$reader_ref" "$reader" "up=$up_ref"
  pass_record leaf "$leaf_ref" "$leaf" "reader=wt/reader@$base"
  combined_record "integration/task@$joined" "$base" PASS "up=$up_ref" "reader=$reader_ref" "leaf=$leaf_ref"
} > "$evidence"
run_check 1 'does not match hard dependency' join
read_ref="wt/up@$old_up"
write_join_evidence
run_check 1 'intersects read' join
read_ref="$up_ref"
write_join_evidence
cat > "$plan" <<'EOF'
id: leaf
write: leaf/
depends: reader

id: reader
write: reader/
read: shared/read.txt
read_depends: up

id: up
write: up/
EOF
run_check 1 'stream up ownership check failed' join
write_plan

printf 'untracked integration file\n' > "$int/stray"
run_check 1 'integration dirty worktree' join
run_check 1 'integration dirty worktree' env GIT_DIR="$repo/.git" GIT_WORK_TREE="$repo" \
  "$checker" join --plan "$plan" --base-ref "$base_ref" --integration-ref "integration/task@$joined" \
  --integration-worktree "$int" "$evidence"
rm -- "$int/stray"
printf 'unauthorized commit\n' > "$int/extra"
integration_head="$(commit_all "$int" 'unplanned integration commit')"
write_join_evidence
run_check 1 'integration contains a commit outside planned histories' join
run_check 1 'unplanned integration path: extra' join
integration_head="$(git -C "$int" commit-tree "${joined}^{tree}" -p "$joined" -p "$initial" -m 'attach pre-base parent')"
git -C "$int" reset -q --hard "$integration_head"
write_join_evidence
run_check 1 'unreviewed parent' join
integration_head="$(git -C "$int" commit-tree "${joined}^{tree}" -p "$joined" -p "$old_up" -m 'attach a partial stream')"
git -C "$int" reset -q --hard "$integration_head"
write_join_evidence
run_check 1 "unreviewed parent: $old_up" join

git -C "$int" reset -q --hard "$base"
git -C "$int" merge -q --no-ff --no-commit "$up_head" > /dev/null 2>&1
printf 'unplanned merge content\n' > "$int/extra"
foreign_merge="$(commit_all "$int" 'add unplanned merge content')"
git -C "$int" merge -q --no-ff --no-commit "$reader_head" > /dev/null 2>&1
rm -- "$int/extra"
commit_all "$int" 'remove unplanned merge content' > /dev/null
git -C "$int" merge -q --no-ff -m 'land leaf' "$leaf_head"
integration_head="$(git -C "$int" rev-parse HEAD)"
[[ "$(git -C "$int" rev-parse HEAD^{tree})" == "$(git -C "$int" rev-parse "${joined}^{tree}")" ]] ||
  fail 'tainted merge fixture has a different final tree'
write_join_evidence
run_check 1 "unplanned integration path: extra (commit $foreign_merge)" join

git -C "$int" reset -q --hard "$pre_leaf"
git -C "$int" merge -q --no-ff --no-commit "$leaf_head" > /dev/null 2>&1
printf 'unreviewed merge resolution\n' > "$int/reader/result"
integration_head="$(commit_all "$int" 'modify planned path in merge only')"
write_join_evidence
run_check 1 'integration path differs from planned patch: reader/result' join

# Populated gitlinks are unsupported, even when Git reports them clean.
sub="$tmp/sub"
sub_parent="$tmp/sub-parent"
new_repo "$sub"
printf 'versioned\n' > "$sub/data"
commit_all "$sub" 'submodule base' > /dev/null
new_repo "$sub_parent"
git -C "$sub_parent" -c protocol.file.allow=always submodule add -q "$sub" dependency
git -C "$sub_parent" config submodule.dependency.ignore all
base="$(commit_all "$sub_parent" 'install submodule')"
base_ref="main@$base"
repo="$sub_parent"
cat > "$plan" <<'EOF'
id: up
write: root-file

id: reader
depends: up
EOF
git -C "$sub_parent" switch -qc wt/sub-parent
printf 'own patch\n' > "$sub_parent/root-file"
sub_parent_head="$(commit_all "$sub_parent" 'add owned path')"
pass_record up "wt/sub-parent@$sub_parent_head" "$sub_parent" > "$evidence"
run_check 1 'populated or unreadable submodule path is unsupported: dependency' check ready --stream reader
git -C "$sub_parent" submodule deinit --force -- dependency > /dev/null
mkdir -p "$sub_parent/dependency"
run_check 0 'GRAPH READY PASS' check ready --stream reader
printf 'populated without an initialized worktree\n' > "$sub_parent/dependency/data"
run_check 1 'populated or unreadable submodule path is unsupported: dependency' check ready --stream reader

printf 'graph E2E PASS\n'
