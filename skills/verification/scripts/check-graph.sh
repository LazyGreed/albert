#!/usr/bin/env bash
# Read-only gates for a coordinator's declared v2 graph and recorded verdicts.
set -euo pipefail
export LC_ALL=C

# Discover each supplied repository and use its recorded commit history.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_INDEX_FILE \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH \
  GIT_NAMESPACE GIT_PREFIX GIT_SHALLOW_FILE GIT_REPLACE_REF_BASE \
  GIT_CONFIG GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
  GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_EXTERNAL_DIFF
export GIT_OPTIONAL_LOCKS=0 GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null GIT_NO_LAZY_FETCH=1 GIT_ADVICE=0

usage() {
  cat <<'USAGE'
Usage:
  check-graph.sh ready --plan PLAN --base-ref BRANCH@SHA [--stream ID] [--repo DIR] EVIDENCE
  check-graph.sh invalidate --plan PLAN --base-ref BRANCH@SHA [--stream ID] [--repo DIR] EVIDENCE
  check-graph.sh join --plan PLAN --base-ref BRANCH@SHA --integration-ref BRANCH@SHA
                      --integration-worktree DIR [--repo DIR] EVIDENCE

Commands share graph, ownership, and evidence validation. Ready checks the
selected streams' prerequisites. Invalidate checks selected streams and their
prerequisites. Omit --stream to select all planned streams. Join checks all
planned streams, integration history, and a separate combined PASS.

Files use blank-line-separated records with one key: value per line.
  Plan: id, write, read, depends (hard), read_depends (read-only).
  Stream evidence: id, ref, worktree, status, verdict_ref, verdict_base,
                   verified_against (ID=BRANCH@SHA).
  Combined evidence: status, integration_ref, verdict_base, input_ref (ID=BRANCH@SHA).
Repeat path, edge, or input fields for distinct values. Verdict bases are bare
commit SHAs. Abbreviations must resolve unambiguously and use at least 7 hex digits.
EVIDENCE may be empty at initial readiness. --repo overrides base lookup, which
otherwise uses integration, a required stream's worktree, or the current directory.
Set TMPDIR outside Git repositories for scratch files. Bound worktrees with
populated submodule paths or hidden index entries are unsupported.
USAGE
}

die_usage() {
  printf 'check-graph: %s\n' "$1" >&2
  usage >&2
  exit 2
}

die_record() {
  printf 'check-graph: %s\n' "$1" >&2
  exit 2
}

failures=()
scratch=""
trap 'if [[ -n "$scratch" ]]; then rm -rf -- "$scratch"; fi' EXIT
ownership_checker="$(dirname -- "${BASH_SOURCE[0]}")/check-ownership.sh"

note_fail() {
  failures+=("$1")
}

finish() {
  local prefix="GRAPH ${command^^}" message
  if (( ${#failures[@]} )); then
    for message in "${failures[@]}"; do
      printf '%s FAIL: %s\n' "$prefix" "$message" >&2
    done
    exit 1
  fi
  printf '%s PASS\n' "$prefix"
  exit 0
}

trim() {
  trimmed="${1#"${1%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
}

split_fields() {
  local -n items=$2
  items=()
  if [[ -n "$1" ]]; then
    mapfile -t items <<< "$1"
  fi
}

valid_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,64}$ ]]
}

parse_ref() {
  ref_branch="${1%@*}"
  ref_sha="${1##*@}"
  [[ "$ref_branch" != "$1" ]] && valid_sha "$ref_sha" &&
    git check-ref-format "refs/heads/$ref_branch"
}

normalize_pattern() {
  pattern="$1"
  while [[ "$pattern" == ./* ]]; do
    pattern="${pattern#./}"
  done
  [[ -n "$pattern" && "$pattern" != /* && "$pattern" != *//* &&
    "/$pattern/" != */./* && "/$pattern/" != */../* ]] || die_record "invalid path pattern: $1"
  if [[ "$pattern" == */ ]]; then
    pattern+="**"
  fi
}

declare -a ids=()
declare -A planned=() plan=() observed=() evidence=() combined=()
declare -A edge_kind=() upstreams=() edge_refs=() join_refs=()

parse_record() {
  local source="$1" line key value attribute id
  shift
  local -A fields=() seen=()
  for line in "$@"; do
    [[ "$line" == *:* ]] || die_record "invalid $source line: $line"
    trim "${line%%:*}"
    key="$trimmed"
    trim "${line#*:}"
    value="$trimmed"
    [[ -n "$value" ]] || die_record "empty $source field: $key"
    case "$source:$key" in
      plan:id|evidence:id)
        [[ "$value" =~ ^[[:alnum:]_.-]+$ ]] || die_record "invalid stream id: $value"
        ;;
      plan:write|plan:read)
        normalize_pattern "$value"
        value="$pattern"
        ;;
      plan:depends|plan:read_depends|evidence:worktree|evidence:verified_against|evidence:input_ref) ;;
      evidence:status)
        case "$value" in
          PASS|FAIL|'NOT RUN'|BLOCKED) ;;
          *) die_record "invalid verdict status: $value" ;;
        esac
        ;;
      evidence:ref|evidence:verdict_ref|evidence:integration_ref)
        parse_ref "$value" || die_record "invalid $key: $value"
        ;;
      evidence:verdict_base)
        valid_sha "$value" || die_record "invalid verdict_base: $value"
        ;;
      *) die_record "unknown $source field: $key" ;;
    esac
    case "$key" in
      write|read|depends|read_depends|verified_against|input_ref) attribute="$key:$value" ;;
      *) attribute="$key" ;;
    esac
    [[ -z "${seen[$attribute]+x}" ]] || die_record "duplicate $source attribute: $attribute"
    seen[$attribute]=1
    fields[$key]="${fields[$key]:+${fields[$key]}$'\n'}$value"
  done

  id="${fields[id]:-}"
  if [[ "$source" == plan ]]; then
    [[ -n "$id" ]] || die_record "plan record missing id"
    [[ -z "${planned[$id]+x}" ]] || die_record "duplicate planned stream: $id"
    ids+=("$id")
    planned[$id]=1
    for key in write read depends read_depends; do
      plan[$id:$key]="${fields[$key]:-}"
    done
  elif [[ -n "$id" ]]; then
    [[ -n "${planned[$id]+x}" ]] || die_record "evidence for unplanned stream: $id"
    [[ -z "${observed[$id]+x}" ]] || die_record "duplicate stream evidence: $id"
    [[ -z "${fields[integration_ref]+x}${fields[input_ref]+x}" ]] ||
      die_record "combined evidence fields on stream: $id"
    observed[$id]=1
    for key in ref worktree status verdict_ref verdict_base verified_against; do
      evidence[$id:$key]="${fields[$key]:-}"
    done
  else
    [[ -n "${fields[integration_ref]+x}" ]] || die_record "evidence record missing id or integration_ref"
    [[ -z "${combined[integration_ref]+x}" ]] || die_record "duplicate combined evidence"
    [[ -z "${fields[ref]+x}${fields[worktree]+x}${fields[verdict_ref]+x}${fields[verified_against]+x}" ]] ||
      die_record "stream evidence fields on combined record"
    for key in status integration_ref verdict_base input_ref; do
      combined[$key]="${fields[$key]:-}"
    done
  fi
}

parse_file() {
  local source="$1" path="$2" line
  local -a lines=()
  [[ -f "$path" && -r "$path" ]] || die_record "cannot read $source file: $path"
  if IFS= read -r -d '' line < "$path"; then
    die_record "NUL byte in $source file: $path"
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
      if (( ${#lines[@]} )); then
        parse_record "$source" "${lines[@]}"
        lines=()
      fi
    else
      lines+=("$line")
    fi
  done < "$path"
  if (( ${#lines[@]} )); then
    parse_record "$source" "${lines[@]}"
  fi
}

# Match the path glob syntax in check-ownership.sh. P represents optional **/.
compile_tokens() {
  local pattern="$1" i=0 ch
  local -n compiled=$2
  compiled=()
  while (( i < ${#pattern} )); do
    if [[ "${pattern:i:3}" == '**/' ]] && { (( i == 0 )) || [[ "${pattern:i-1:1}" == / ]]; }; then
      compiled+=(P)
      i=$((i + 3))
    elif [[ "${pattern:i:2}" == '**' ]]; then
      compiled+=(G)
      i=$((i + 2))
    else
      ch="${pattern:i:1}"
      case "$ch" in
        '*') compiled+=(S) ;;
        '?') compiled+=(Q) ;;
        *) compiled+=("L$ch") ;;
      esac
      i=$((i + 1))
    fi
  done
}

read_regex() {
  local -a tokens
  local token ch
  compile_tokens "$1" tokens
  regex='^'
  for token in "${tokens[@]}"; do
    case "$token" in
      P) regex+='(.*/)?' ;;
      G) regex+='.*' ;;
      S) regex+='[^/]*' ;;
      Q) regex+='[^/]' ;;
      L*)
        ch="${token:1}"
        case "$ch" in
          '.'|'+'|'('|')'|'{'|'}'|'^'|'$'|'|'|'\'|'['|']') regex+='\' ;;
        esac
        regex+="$ch"
        ;;
    esac
  done
  regex+='$'
}

# Walk the product of two glob automata. Each move either stays at the current
# token or advances, so a move that leaves both positions unchanged adds no path.
move_options() {
  local token="$1" position="$2" prefix="$3"
  local -n chars=$4 positions=$5 prefixes=$6
  chars=() positions=() prefixes=()
  case "$token:$prefix" in
    P:1) chars=(G 'L/') positions=("$position" "$((position + 1))") prefixes=(1 0) ;;
    G:0|S:0) chars=("$token") positions=("$position") prefixes=(0) ;;
    Q:0) chars=(S) positions=("$((position + 1))") prefixes=(0) ;;
    L*:0) chars=("$token") positions=("$((position + 1))") prefixes=(0) ;;
  esac
}

intersects() {
  local i="$1" j="$2" pa="$3" pb="$4" key="$1,$2,$3,$4"
  local a="${tokens_a[$i]:-}" b="${tokens_b[$j]:-}"
  if [[ -n "${disjoint[$key]+x}" ]]; then
    return 1
  fi
  [[ -n "$a$b" ]] || return 0
  if (( ! pa )); then
    case "$a" in
      P|G|S) if intersects "$((i + 1))" "$j" 0 "$pb"; then return 0; fi ;;
    esac
    if [[ "$a" == P ]] && intersects "$i" "$j" 1 "$pb"; then return 0; fi
  fi
  if (( ! pb )); then
    case "$b" in
      P|G|S) if intersects "$i" "$((j + 1))" "$pa" 0; then return 0; fi ;;
    esac
    if [[ "$b" == P ]] && intersects "$i" "$j" "$pa" 1; then return 0; fi
  fi

  local -a ac ai ap bc bi bp
  move_options "$a" "$i" "$pa" ac ai ap
  move_options "$b" "$j" "$pb" bc bi bp
  local x y
  for x in "${!ac[@]}"; do
    for y in "${!bc[@]}"; do
      if (( ai[x] == i && bi[y] == j && ap[x] == pa && bp[y] == pb )); then
        continue
      fi
      if [[ "${ac[$x]}" == G || "${bc[$y]}" == G || "${ac[$x]}" == "${bc[$y]}" ||
            ( "${ac[$x]}" == S && "${bc[$y]}" != 'L/' ) ||
            ( "${bc[$y]}" == S && "${ac[$x]}" != 'L/' ) ]]; then
        if intersects "${ai[$x]}" "${bi[$y]}" "${ap[$x]}" "${bp[$y]}"; then return 0; fi
      fi
    done
  done
  disjoint[$key]=1
  return 1
}

patterns_overlap() {
  local -a tokens_a tokens_b
  local -A disjoint=()
  compile_tokens "$1" tokens_a
  compile_tokens "$2" tokens_b
  intersects 0 0 0 0
}

declare -A visited=()
declare -a order=()

visit() {
  local id="$1" path="$2" upstream
  case "${visited[$id]:-}" in
    done) return 0 ;;
    active) note_fail "cycle: $path$id"; return 1 ;;
  esac
  local -a inputs
  split_fields "${upstreams[$id]:-}" inputs
  visited[$id]=active
  for upstream in "${inputs[@]}"; do
    visit "$upstream" "$path$id -> " || return 1
  done
  visited[$id]=done
  order+=("$id")
}

validate_graph() {
  local id kind upstream writer write read left right
  local -a edges writes reads left_writes right_writes
  for id in "${ids[@]}"; do
    for kind in depends read_depends; do
      split_fields "${plan[$id:$kind]}" edges
      for upstream in "${edges[@]}"; do
        if [[ -z "${planned[$upstream]+x}" ]]; then
          note_fail "unknown $kind edge: $id -> $upstream"
        elif [[ -n "${edge_kind[$id:$upstream]+x}" ]]; then
          note_fail "edge declared as hard and read-only: $id -> $upstream"
        else
          edge_kind[$id:$upstream]="$kind"
          upstreams[$id]="${upstreams[$id]:+${upstreams[$id]}$'\n'}$upstream"
        fi
      done
    done
    if [[ -n "${plan[$id:read_depends]}" && -z "${plan[$id:read]}" ]]; then
      note_fail "read-only dependencies require read paths: $id"
    fi
  done
  if (( ${#failures[@]} )); then finish; fi

  local i j
  for i in "${!ids[@]}"; do
    left="${ids[$i]}"
    split_fields "${plan[$left:write]}" left_writes
    for ((j = i + 1; j < ${#ids[@]}; j++)); do
      right="${ids[$j]}"
      split_fields "${plan[$right:write]}" right_writes
      for write in "${left_writes[@]}"; do
        for read in "${right_writes[@]}"; do
          if patterns_overlap "$write" "$read"; then
            note_fail "write/write overlap: $left and $right ($write vs $read)"
          fi
        done
      done
    done
  done
  for id in "${ids[@]}"; do
    split_fields "${plan[$id:read]}" reads
    for writer in "${ids[@]}"; do
      [[ "$writer" != "$id" && -z "${edge_kind[$id:$writer]+x}" ]] || continue
      split_fields "${plan[$writer:write]}" writes
      for read in "${reads[@]}"; do
        for write in "${writes[@]}"; do
          if patterns_overlap "$read" "$write"; then
            note_fail "read/write overlap without dependency: $id reads $writer ($read vs $write)"
          fi
        done
      done
    done
    visit "$id" "" || break
  done
  if (( ${#failures[@]} )); then finish; fi
}

validate_input_refs() {
  local stream="$1" values="$2" entry id ref key
  local -n refs=$3
  local -a entries
  split_fields "$values" entries
  for entry in "${entries[@]}"; do
    id="${entry%%=*}"
    ref="${entry#*=}"
    [[ -n "$id" && "$entry" == *=* ]] && parse_ref "$ref" ||
      die_record "invalid input ref on $stream: $entry"
    [[ -n "${planned[$id]+x}" ]] || die_record "input ref for unplanned stream: $stream -> $id"
    key="$id"
    if [[ "$stream" != '(join)' ]]; then
      key="$stream:$id"
      [[ -n "${edge_kind[$key]+x}" ]] || die_record "verified_against for undeclared edge: $stream -> $id"
    fi
    [[ -z "${refs[$key]+x}" ]] || die_record "duplicate input ref: $stream -> $id"
    refs[$key]="$ref"
  done
}

resolve_commit() {
  local sha="$2" resolved
  valid_sha "$sha" || return 1
  resolved="$(git -C "$1" rev-parse --verify --end-of-options "${sha,,}^{commit}" 2>/dev/null)" || return 1
  [[ "$resolved" == "${sha,,}"* ]] || return 1
  printf '%s\n' "$resolved"
}

matches_ref() {
  local resolved
  parse_ref "$2" && [[ "$ref_branch" == "$3" ]] &&
    resolved="$(resolve_commit "$1" "$ref_sha")" && [[ "$resolved" == "$4" ]]
}

check_base() {
  local dir="$1" tip
  base_common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
    note_fail "base repository unavailable: $dir"
    finish
  }
  parse_ref "$base_ref" || die_usage "invalid --base-ref: $base_ref"
  base_branch="$ref_branch"
  if ! tip="$(git -C "$dir" show-ref --verify --hash "refs/heads/$base_branch" 2>/dev/null)"; then
    note_fail "base branch unavailable: $ref_branch"
    finish
  fi
  if ! base_sha="$(resolve_commit "$dir" "$ref_sha")" || [[ "$base_sha" != "$tip" ]]; then
    note_fail "base ref stale: expected $base_ref got $ref_branch@$tip"
    finish
  fi
}

run_ownership() {
  # Keep older installations' Git diff and status settings from hiding changes.
  TMPDIR="$scratch" GIT_CONFIG_COUNT=8 \
    GIT_CONFIG_KEY_0=diff.ignoreSubmodules GIT_CONFIG_VALUE_0=none \
    GIT_CONFIG_KEY_1=diff.relative GIT_CONFIG_VALUE_1=false \
    GIT_CONFIG_KEY_2=core.ignoreCase GIT_CONFIG_VALUE_2=false \
    GIT_CONFIG_KEY_3=core.filemode GIT_CONFIG_VALUE_3=true \
    GIT_CONFIG_KEY_4=core.fsmonitor GIT_CONFIG_VALUE_4=false \
    GIT_CONFIG_KEY_5=core.untrackedCache GIT_CONFIG_VALUE_5=false \
    GIT_CONFIG_KEY_6=core.trustctime GIT_CONFIG_VALUE_6=true \
    GIT_CONFIG_KEY_7=core.checkStat GIT_CONFIG_VALUE_7=default \
    "$ownership_checker" "$@" > /dev/null
}

unpopulated_gitlink() (
  local path="$1"
  [[ ! -L "$path" ]] || return 1
  [[ -e "$path" ]] || return 0
  [[ -d "$path" && -r "$path" && -x "$path" ]] || return 1
  unset GLOBIGNORE
  shopt -s nullglob dotglob
  local -a entries=("$path"/*)
  (( ! ${#entries[@]} ))
)

check_worktree_clean() {
  local label="$1" dir="$2" head="$3" entry status path
  if ! git -C "$dir" ls-files -v -z > "$git_output"; then
    note_fail "$label index unreadable"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    if [[ "$entry" == [a-zS]' '* ]]; then
      note_fail "$label hidden index path: ${entry:2} (assume-unchanged or skip-worktree)"
      return 1
    fi
  done < "$git_output"

  if ! git -C "$dir" ls-tree -r -z "$head" -- > "$git_output"; then
    note_fail "$label committed tree unreadable"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    [[ "$entry" == '160000 commit '* ]] || continue
    path="${entry#*$'\t'}"
    if ! unpopulated_gitlink "$dir/$path"; then
      note_fail "$label populated or unreadable submodule path is unsupported: $path"
      return 1
    fi
  done < "$git_output"

  # A literal dot cannot match any repository-relative Git path.
  if ! run_ownership --base "$head" --worktree "$dir" -- .; then
    note_fail "$label dirty worktree or unreadable changes"
    return 1
  fi
  if ! status="$(git -C "$dir" -c core.fsmonitor=false status --porcelain --untracked-files=all --ignore-submodules=none)"; then
    note_fail "$label status unreadable"
    return 1
  elif [[ -n "$status" ]]; then
    note_fail "$label dirty worktree"
    return 1
  fi
}

# On success, expose the branch and commit of the bound worktree.
check_checkout() {
  local label="$1" dir="$2" ref="$3" top common
  checkout_branch="" checkout_head=""
  if [[ -z "$dir" ]] || ! top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" ||
    [[ ! "$top" -ef "$dir" ]]; then
    note_fail "$label worktree unavailable or not a worktree root: ${dir:-missing}"
    return 1
  fi
  if ! common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" ||
    [[ ! "$common" -ef "$base_common" ]]; then
    note_fail "$label worktree repository differs from base repository: $dir"
    return 1
  fi
  if ! checkout_branch="$(git -C "$dir" symbolic-ref HEAD 2>/dev/null)" ||
    [[ "$checkout_branch" != refs/heads/* ]] ||
    ! checkout_head="$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null)" ||
    ! matches_ref "$dir" "$ref" "${checkout_branch#refs/heads/}" "$checkout_head"; then
    note_fail "$label ref mismatch: expected ${ref:-missing} got ${checkout_branch#refs/heads/}@${checkout_head:-unknown}"
    return 1
  fi
  checkout_branch="${checkout_branch#refs/heads/}"
  check_worktree_clean "$label" "$dir" "$checkout_head"
}

check_verdict_base() {
  local checked_base
  if ! checked_base="$(resolve_commit "$2" "$3")" || [[ "$checked_base" != "$base_sha" ]]; then
    note_fail "$1 verdict BASE mismatch: expected $base_sha got ${3:-missing}"
  fi
}

# Check both paths of each detected rename or copy without shell word splitting.
check_read_diff() {
  local stream="$1" upstream="$2" dir="$3" old="$4" current="$5"
  local status path re
  local -a reads regexes=()
  split_fields "${plan[$stream:read]}" reads
  for path in "${reads[@]}"; do
    read_regex "$path"
    regexes+=("$regex")
  done
  if ! git -C "$dir" diff --name-status -z -M -C --find-copies-harder -l0 \
    --no-relative --no-ext-diff --no-textconv --ignore-submodules=none -O/dev/null "$old..$current" -- > "$git_output"; then
    note_fail "stale: $stream -> $upstream unreadable diff"
    return 1
  fi
  while IFS= read -r -d '' status; do
    local count=1
    if [[ "$status" == [RC]* ]]; then count=2; fi
    while (( count-- > 0 )); do
      if ! IFS= read -r -d '' path; then
        note_fail "stale: $stream -> $upstream incomplete diff"
        return 1
      fi
      for re in "${regexes[@]}"; do
        if [[ "$path" =~ $re ]]; then
          note_fail "stale: $stream -> $upstream intersects read via $path"
          return 1
        fi
      done
    done
  done < "$git_output"
}

check_owned_patch() {
  local id="$1" dir="$2" head="$3" history commit parent current="$3"
  if ! git -C "$dir" merge-base --is-ancestor "$base_sha" "$head"; then
    note_fail "stream $id ownership baseline is outside stream ancestry: $base_sha"
    return 1
  fi
  local -a writes ancestry
  split_fields "${plan[$id:write]}" writes
  if (( ! ${#writes[@]} )); then
    note_fail "stream $id has no declared write ownership"
    return 1
  fi
  if ! run_ownership --repo "$dir" --base "$base_sha" --head "$head" --require-changes -- "${writes[@]}"; then
    note_fail "stream $id ownership check failed"
    return 1
  fi
  if ! history="$(git -C "$dir" rev-list --parents --topo-order "$base_sha..$head" --)"; then
    note_fail "stream $id ownership history unreadable"
    return 1
  fi
  while IFS=' ' read -r -a ancestry; do
    if (( ${#ancestry[@]} != 2 )) || [[ "${ancestry[0]}" != "$current" ]]; then
      note_fail "stream $id ownership requires a patch without merge commits above BASE"
      return 1
    fi
    commit="${ancestry[0]}"
    parent="${ancestry[1]}"
    if [[ "$parent" != "$base_sha" || "$commit" != "$head" ]] &&
      ! run_ownership --repo "$dir" --base "$parent" --head "$commit" -- "${writes[@]}"; then
      note_fail "stream $id ownership check failed at commit $commit"
      return 1
    fi
    current="$parent"
  done <<< "$history"
  if [[ "$current" != "$base_sha" ]]; then
    note_fail "stream $id ownership history does not reach BASE"
    return 1
  fi
}

declare -A required=() valid=() heads=() branches=()

require_stream() {
  local id="$1" upstream
  [[ -z "${required[$id]+x}" ]] || return 0
  required[$id]=1
  local -a inputs
  split_fields "${upstreams[$id]:-}" inputs
  for upstream in "${inputs[@]}"; do
    require_stream "$upstream"
  done
}

check_edge() {
  local id="$1" upstream="$2" ref="${edge_refs[$1:$2]:-}"
  local kind="${edge_kind[$id:$upstream]}" dir="${evidence[$upstream:worktree]:-}" old
  if [[ -z "$ref" ]]; then
    note_fail "missing verified_against: $id -> $upstream ($kind)"
  elif [[ -z "${valid[$upstream]+x}" ]]; then
    note_fail "stale: $id -> $upstream has no current PASS"
  elif [[ "$kind" == depends ]]; then
    if ! matches_ref "$dir" "$ref" "${branches[$upstream]}" "${heads[$upstream]}"; then
      note_fail "stale: $id -> $upstream verified_against $ref does not match hard dependency ${branches[$upstream]}@${heads[$upstream]}"
    fi
  else
    parse_ref "$ref" || die_record "invalid verified_against ref: $ref"
    if [[ "$ref_branch" != "${branches[$upstream]}" ]] || ! old="$(resolve_commit "$dir" "$ref_sha")"; then
      note_fail "stale: $id -> $upstream invalid historical read ref $ref"
    elif [[ "$old" != "${heads[$upstream]}" ]]; then
      if ! git -C "$dir" merge-base --is-ancestor "$old" "${heads[$upstream]}"; then
        note_fail "stale: $id -> $upstream historical read ref $ref is outside upstream ancestry"
      elif ! git -C "$dir" merge-base --is-ancestor "$base_sha" "$old"; then
        note_fail "stale: $id -> $upstream historical read ref $ref predates BASE"
      else
        check_read_diff "$id" "$upstream" "$dir" "$old" "${heads[$upstream]}" || return 1
      fi
    fi
  fi
}

check_streams() {
  local id dir ref upstream before
  local -a inputs
  for id in "${order[@]}"; do
    [[ -n "${required[$id]+x}" ]] || continue
    if [[ "${evidence[$id:status]:-}" != PASS ]]; then
      note_fail "stream not PASS: $id (status: ${evidence[$id:status]:-missing})"
      continue
    fi
    dir="${evidence[$id:worktree]:-}"
    ref="${evidence[$id:ref]:-}"
    check_checkout "stream $id" "$dir" "$ref" || continue
    heads[$id]="$checkout_head"
    branches[$id]="$checkout_branch"
    before=${#failures[@]}
    if ! matches_ref "$dir" "${evidence[$id:verdict_ref]:-}" "$checkout_branch" "$checkout_head"; then
      note_fail "stream $id verdict REF mismatch: expected $checkout_branch@$checkout_head got ${evidence[$id:verdict_ref]:-missing}"
    fi
    check_verdict_base "stream $id" "$dir" "${evidence[$id:verdict_base]:-}"
    check_owned_patch "$id" "$dir" "$checkout_head" || continue
    split_fields "${upstreams[$id]:-}" inputs
    for upstream in "${inputs[@]}"; do
      check_edge "$id" "$upstream" || continue
    done
    if (( ${#failures[@]} == before )); then
      valid[$id]=1
    fi
  done
}

# Raw diffs record the path, mode, and object ID relative to the same BASE.
# Compare them without writing a trial merge tree into the repository.
load_patch() {
  local dir="$1" head="$2" change path
  local -n patch=$3 paths=$4
  if ! git -C "$dir" diff --raw -z --no-abbrev --no-renames --no-relative \
    --no-ext-diff --no-textconv --ignore-submodules=none -O/dev/null "$base_sha" "$head" -- > "$git_output"; then
    return 1
  fi
  while IFS= read -r -d '' change; do
    IFS= read -r -d '' path || return 1
    [[ -n "$path" && -z "${patch[$path]+x}" ]] || return 1
    patch[$path]="$change"
    paths+=("$path")
  done < "$git_output"
}

check_integration_tree() {
  local commit="$1" id path rc
  local -A expected=() actual=()
  local -a expected_paths=() actual_paths=()
  for id in "${ids[@]}"; do
    rc=0
    git -C "$integration_worktree" merge-base --is-ancestor "${heads[$id]}" "$commit" || rc=$?
    case "$rc" in
      0) ;;
      1) continue ;;
      *) note_fail "cannot inspect ancestry of $id at integration commit $commit"; return 1 ;;
    esac
    if ! load_patch "$integration_worktree" "${heads[$id]}" expected expected_paths; then
      note_fail "cannot assemble planned integration patches: $id"
      return 1
    fi
  done
  if ! load_patch "$integration_worktree" "$commit" actual actual_paths; then
    note_fail "cannot read integration patch at commit $commit"
    return 1
  fi
  for path in "${actual_paths[@]}"; do
    if [[ -z "${expected[$path]+x}" ]]; then
      note_fail "unplanned integration path: $path (commit $commit)"
    elif [[ "${actual[$path]}" != "${expected[$path]}" ]]; then
      note_fail "integration path differs from planned patch: $path (commit $commit)"
    fi
  done
  for path in "${expected_paths[@]}"; do
    if [[ -z "${actual[$path]+x}" ]]; then
      note_fail "planned patch missing from integration: $path (commit $commit)"
    fi
  done
}

check_integration_content() {
  local head="$1" id history commit parent
  local -a ancestry commits exclusions=("^$base_sha")
  local -A checked=()
  checked[$base_sha]=1
  for id in "${ids[@]}"; do
    exclusions+=("^${heads[$id]}")
    checked[${heads[$id]}]=1
  done
  if ! history="$(git -C "$integration_worktree" rev-list --reverse --parents --topo-order "$head" "${exclusions[@]}" --)"; then
    note_fail "cannot inspect integration history"
    return 1
  fi
  split_fields "$history" commits
  for commit in "${commits[@]}"; do
    IFS=' ' read -r -a ancestry <<< "$commit"
    commit="${ancestry[0]}"
    if (( ${#ancestry[@]} < 3 )); then
      note_fail "integration contains a commit outside planned histories: $commit"
      continue
    fi
    for parent in "${ancestry[@]:1}"; do
      if [[ -z "${checked[$parent]+x}" ]]; then
        note_fail "integration merge $commit has an unreviewed parent: $parent"
      fi
    done
    check_integration_tree "$commit" || return 1
    checked[$commit]=1
  done
  if [[ "$head" != "${commit:-}" || -z "${checked[$head]+x}" ]]; then
    check_integration_tree "$head" || return 1
  fi
}

check_join() {
  check_checkout integration "$integration_worktree" "$integration_ref" || return 1
  local head="$checkout_head" branch="$checkout_branch" id dir
  if [[ "$branch" == "$base_branch" ]]; then
    note_fail "integration branch must differ from the target branch: $branch"
  fi
  if ! git -C "$integration_worktree" merge-base --is-ancestor "$base_sha" "$head"; then
    note_fail "base not in integration history: $base_ref"
  fi
  if [[ "${combined[status]:-}" != PASS ]]; then
    note_fail "combined verdict not PASS (status: ${combined[status]:-missing})"
  fi
  if ! matches_ref "$integration_worktree" "${combined[integration_ref]:-}" "$branch" "$head"; then
    note_fail "combined verdict INTEGRATION_REF mismatch: expected $branch@$head got ${combined[integration_ref]:-missing}"
  fi
  check_verdict_base combined "$integration_worktree" "${combined[verdict_base]:-}"
  for id in "${ids[@]}"; do
    dir="${evidence[$id:worktree]:-}"
    if [[ "$branch" == "${branches[$id]:-}" || ( -n "$dir" && "$integration_worktree" -ef "$dir" ) ]]; then
      note_fail "integration must use a separate branch and worktree from stream $id"
    fi
    if [[ -n "${heads[$id]+x}" ]] &&
      ! git -C "$integration_worktree" merge-base --is-ancestor "${heads[$id]}" "$head"; then
      note_fail "input not in integration history: $id ${branches[$id]}@${heads[$id]}"
    fi
    if [[ -z "${join_refs[$id]+x}" ]]; then
      note_fail "missing combined input_ref: $id"
    elif [[ -z "${heads[$id]+x}" ]] ||
      ! matches_ref "$integration_worktree" "${join_refs[$id]}" "${branches[$id]}" "${heads[$id]}"; then
      note_fail "combined input_ref mismatch: $id ${join_refs[$id]}"
    fi
  done
  if (( ! ${#failures[@]} )); then
    check_integration_content "$head" || return 1
  fi
}

case "${1:-}" in
  -h|--help|help) usage; exit 0 ;;
  ready|invalidate|join) command="$1"; shift ;;
  *) die_usage "expected ready, invalidate, or join" ;;
esac

declare -A options=()
while (( $# )); do
  case "$1" in
    --plan|--repo|--base-ref|--stream|--integration-ref|--integration-worktree)
      [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die_usage "$1 requires an argument"
      [[ -z "${options[$1]+x}" ]] || die_usage "duplicate option: $1"
      options[$1]="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) die_usage "unknown option: $1" ;;
    *) break ;;
  esac
done
(( $# == 1 )) || die_usage "expected one EVIDENCE file after the options"
plan_file="${options[--plan]:-}"
base_ref="${options[--base-ref]:-}"
repo_dir="${options[--repo]:-}"
selected="${options[--stream]:-}"
integration_ref="${options[--integration-ref]:-}"
integration_worktree="${options[--integration-worktree]:-}"
[[ -n "$plan_file" ]] || die_usage "--plan is required"
[[ -n "$base_ref" ]] || die_usage "--base-ref is required"
if [[ "$command" == join ]]; then
  [[ -z "$selected" ]] || die_usage "--stream is only valid with ready and invalidate"
  [[ -n "$integration_ref" ]] || die_usage "--integration-ref is required for join"
  [[ -n "$integration_worktree" ]] || die_usage "--integration-worktree is required for join"
else
  [[ -z "$integration_ref$integration_worktree" ]] || die_usage "integration options are only valid with join"
fi

[[ ! "$plan_file" -ef "$1" ]] || die_usage "plan and evidence must be separate files"
parse_file plan "$plan_file"
(( ${#ids[@]} )) || die_record "plan has no stream records"
[[ -z "$selected" || -n "${planned[$selected]+x}" ]] || die_usage "unknown --stream: $selected"
validate_graph
parse_file evidence "$1"
for id in "${ids[@]}"; do
  validate_input_refs "$id" "${evidence[$id:verified_against]:-}" edge_refs
done
validate_input_refs '(join)' "${combined[input_ref]:-}" join_refs

for id in "${ids[@]}"; do
  [[ -z "$selected" || "$id" == "$selected" ]] || continue
  if [[ "$command" == ready ]]; then
    split_fields "${upstreams[$id]:-}" inputs
    for upstream in "${inputs[@]}"; do
      require_stream "$upstream"
    done
  else
    require_stream "$id"
  fi
done
if [[ -z "$repo_dir" ]]; then
  repo_dir="$integration_worktree"
  for id in "${order[@]}"; do
    [[ -z "$repo_dir" ]] || break
    if [[ -n "${required[$id]+x}" && -n "${evidence[$id:worktree]:-}" ]]; then
      repo_dir="${evidence[$id:worktree]}"
    fi
  done
fi
check_base "${repo_dir:-.}"
scratch_root="$(cd -P -- "${TMPDIR:-/tmp}" && pwd -P)" || die_usage "temporary directory is unavailable"
if git -C "$scratch_root" rev-parse --git-dir >/dev/null 2>&1; then
  die_usage "temporary directory must be outside Git repositories: $scratch_root"
fi
scratch="$(mktemp -d "$scratch_root/quintet-graph.XXXXXXXX")"
git_output="$scratch/git-output"
check_streams
if [[ "$command" == join ]]; then
  check_join || finish
fi
finish
