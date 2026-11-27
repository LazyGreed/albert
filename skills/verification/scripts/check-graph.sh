#!/usr/bin/env bash
# Fail-closed checks for v2 stream graphs: ready, invalidate, and join.
# Spec records are blank-line separated. Repeat keys for multiple values.
# The spec file is only read. Nothing is written into the caller's repository.
set -euo pipefail
LC_ALL=C

usage() {
  cat <<'USAGE'
Usage:
  check-graph.sh ready [--repo <dir>] <spec>
  check-graph.sh invalidate [--repo <dir>] <spec>
  check-graph.sh join --integration-ref <branch@sha> --integration-worktree <dir> [--repo <dir>] <spec>

Commands:
  ready        Reject unknown dependencies, dependency cycles, mutual read/write
               cycles, write/write overlaps, and a read of another stream's write
               unless the reader depends on that writer. A depends target must be
               status PASS, with a worktree whose branch and HEAD equal ref.
               A missing worktree is not a pass. Missing status is not a pass.
  invalidate   Require each stream worktree clean and its branch plus HEAD equal
               to ref. A verified_against input is stale when its old sha is missing
               or the upstream diff intersects that stream's read patterns, including
               either path of a rename or copy. A non-overlapping diff is not stale.
  join         Require a clean integration checkout at --integration-ref and every
               input status PASS with a worktree whose branch and HEAD equal ref.
               A missing, stale, or dirty binding fails. An object in the
               integration repo is not an input binding.

Spec fields:
  id, write, read, depends, status, ref (branch@sha, sha at least 7 hex),
  worktree, verified_against (id@sha). Repeat write, read, depends, and
  verified_against for multiple values. Separate records with a blank line.

Options:
  --repo <dir>                 Accepted and ignored. Ref binding uses each stream
                               worktree, never this directory or the current one.
  --integration-ref <branch@sha>
                               Required for join.
  --integration-worktree <dir> Required for join.
  -h, --help                   Show this help message.
USAGE
}

die_usage() {
  echo "check-graph: $1" >&2
  usage >&2
  exit 2
}

die_spec() {
  echo "check-graph: $1" >&2
  exit 2
}

integration_ref=""
integration_worktree=""
spec_file=""
cmd=""

RESULT_PREFIX=""
FAILURES=()
TMP_FILES=()

cleanup() {
  local f
  for f in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do
    rm -f -- "$f"
  done
}
trap cleanup EXIT

note_fail() {
  FAILURES+=("$1")
}

finish() {
  local msg
  if (( ${#FAILURES[@]} > 0 )); then
    for msg in "${FAILURES[@]}"; do
      printf '%s FAIL: %s\n' "$RESULT_PREFIX" "$msg" >&2
    done
    exit 1
  fi
  printf '%s PASS\n' "$RESULT_PREFIX"
  exit 0
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

declare -a IDS=()
declare -a STATUSES=()
declare -a REFS=()
declare -a WORKTREES=()
declare -a WRITES=()
declare -a READS=()
declare -a DEPS=()
declare -a VERIFIED=()
declare -A ID_INDEX=()

split_fields() {
  local data="$1"
  local -n dest=$2
  dest=()
  [[ -n "$data" ]] || return 0
  local item
  while IFS= read -r item || [[ -n "$item" ]]; do
    [[ -n "$item" ]] && dest+=("$item")
  done <<< "$data"
}

parse_at_sha() {
  local ref="$1"
  AT_LEFT=""
  AT_SHA=""
  local sha="${ref##*@}"
  local left="${ref%@*}"
  if [[ -z "$left" || "$left" == "$ref" || -z "$sha" ]]; then
    return 1
  fi
  if [[ ! "$sha" =~ ^[0-9a-fA-F]{7,}$ ]]; then
    return 1
  fi
  if [[ "$left" == *[[:space:]]* ]]; then
    return 1
  fi
  AT_LEFT="$left"
  AT_SHA="$sha"
  return 0
}

parse_record() {
  local line key val
  local id="" status="" ref="" worktree=""
  local writes="" reads="" deps="" verified=""
  local seen_id=0 seen_status=0 seen_ref=0 seen_wt=0
  for line in "$@"; do
    if [[ "$line" != *:* ]]; then
      die_spec "invalid spec line: $line"
    fi
    key="$(trim "${line%%:*}")"
    val="$(trim "${line#*:}")"
    case "$key" in
      id)
        seen_id=$((seen_id + 1))
        id="$val"
        ;;
      status)
        seen_status=$((seen_status + 1))
        status="$val"
        ;;
      ref)
        seen_ref=$((seen_ref + 1))
        ref="$val"
        ;;
      worktree)
        seen_wt=$((seen_wt + 1))
        worktree="$val"
        ;;
      write)
        [[ -n "$val" ]] || die_spec "empty write pattern"
        if [[ -n "$writes" ]]; then writes+=$'
'"$val"; else writes="$val"; fi
        ;;
      read)
        [[ -n "$val" ]] || die_spec "empty read pattern"
        if [[ -n "$reads" ]]; then reads+=$'
'"$val"; else reads="$val"; fi
        ;;
      depends)
        [[ -n "$val" ]] || die_spec "empty depends value"
        if [[ -n "$deps" ]]; then deps+=$'
'"$val"; else deps="$val"; fi
        ;;
      verified_against)
        [[ -n "$val" ]] || die_spec "empty verified_against value"
        if [[ -n "$verified" ]]; then verified+=$'
'"$val"; else verified="$val"; fi
        ;;
      *)
        die_spec "unknown spec field: $key"
        ;;
    esac
  done
  [[ -n "$id" ]] || die_spec "spec record missing id"
  (( seen_id == 1 )) || die_spec "stream $id must have exactly one id"
  (( seen_status <= 1 )) || die_spec "repeated status for $id"
  (( seen_ref <= 1 )) || die_spec "repeated ref for $id"
  (( seen_wt <= 1 )) || die_spec "repeated worktree for $id"
  if [[ "$id" == *[[:space:]]* ]]; then
    die_spec "invalid id: $id"
  fi
  if [[ -n "${ID_INDEX[$id]+x}" ]]; then
    die_spec "duplicate stream id: $id"
  fi
  local idx=${#IDS[@]}
  IDS+=("$id")
  ID_INDEX[$id]=$idx
  STATUSES+=("$status")
  REFS+=("$ref")
  WORKTREES+=("$worktree")
  WRITES+=("$writes")
  READS+=("$reads")
  DEPS+=("$deps")
  VERIFIED+=("$verified")
}

parse_spec_file() {
  local file="$1"
  [[ -f "$file" && -r "$file" ]] || die_spec "spec not found: $file"
  local line
  local -a lines=()
  flush_record() {
    if (( ${#lines[@]} > 0 )); then
      parse_record "${lines[@]}"
      lines=()
    fi
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*$ ]]; then
      flush_record
    else
      lines+=("$line")
    fi
  done < "$file"
  flush_record
  (( ${#IDS[@]} > 0 )) || die_spec "spec has no stream records"
}

# Convert a path glob into an anchored POSIX ERE. Keep in sync with check-ownership.sh.
glob_to_ere() {
  local pat="$1"
  while [[ "$pat" == ./* ]]; do
    pat="${pat#./}"
  done
  if [[ -z "$pat" ]]; then
    echo "check-graph: empty pattern is not valid" >&2
    return 2
  fi
  if [[ "$pat" == */ ]]; then
    pat="${pat}**"
  fi

  local len=${#pat}
  local i=0
  local ere="^"
  local ch prev

  while (( i < len )); do
    if (( i + 3 <= len )) && [[ "${pat:i:3}" == "**/" ]]; then
      prev=""
      if (( i > 0 )); then
        prev="${pat:i-1:1}"
      fi
      if (( i == 0 )) || [[ "$prev" == "/" ]]; then
        ere+="(.*/)?"
        i=$((i + 3))
        continue
      fi
    fi

    if (( i + 2 <= len )) && [[ "${pat:i:2}" == "**" ]]; then
      ere+=".*"
      i=$((i + 2))
      continue
    fi

    ch="${pat:i:1}"
    case "$ch" in
      '*') ere+="[^/]*" ;;
      '?') ere+="[^/]" ;;
      '.'|'+'|'('|')'|'{'|'}'|'^'|'$'|'|'|'\\'|'['|']') ere+="\\$ch" ;;
      *) ere+="$ch" ;;
    esac
    i=$((i + 1))
  done

  ere+="$"
  printf '%s\n' "$ere"
}

declare -a A_tok=() B_tok=()
declare -a A_MOVE_KIND=() A_MOVE_CHAR=() A_MOVE_NEXT=() A_MOVE_MODE=()
declare -a B_MOVE_KIND=() B_MOVE_CHAR=() B_MOVE_NEXT=() B_MOVE_MODE=()
declare -A INTER_MEMO=() INTER_VIS=()

compile_tokens() {
  local pat="$1"
  local -n out=$2
  out=()
  while [[ "$pat" == ./* ]]; do
    pat="${pat#./}"
  done
  if [[ "$pat" == */ ]]; then
    pat="${pat}**"
  fi
  if [[ -z "$pat" ]]; then
    echo "check-graph: empty pattern is not valid" >&2
    return 2
  fi
  local i=0 len=${#pat} ch prev
  while (( i < len )); do
    if (( i + 3 <= len )) && [[ "${pat:i:3}" == "**/" ]]; then
      prev=""
      if (( i > 0 )); then
        prev="${pat:i-1:1}"
      fi
      if (( i == 0 )) || [[ "$prev" == "/" ]]; then
        out+=("P")
        i=$((i + 3))
        continue
      fi
    fi
    if (( i + 2 <= len )) && [[ "${pat:i:2}" == "**" ]]; then
      out+=("G")
      i=$((i + 2))
      continue
    fi
    ch="${pat:i:1}"
    case "$ch" in
      '*') out+=("S") ;;
      '?') out+=("Q") ;;
      *) out+=("L${ch}") ;;
    esac
    i=$((i + 1))
  done
}

add_move() {
  local side="$1" kind="$2" char="$3" next="$4" mode="$5"
  if [[ "$side" == A ]]; then
    A_MOVE_KIND+=("$kind")
    A_MOVE_CHAR+=("$char")
    A_MOVE_NEXT+=("$next")
    A_MOVE_MODE+=("$mode")
  else
    B_MOVE_KIND+=("$kind")
    B_MOVE_CHAR+=("$char")
    B_MOVE_NEXT+=("$next")
    B_MOVE_MODE+=("$mode")
  fi
}

fill_moves() {
  local side="$1" idx="$2" mode="$3"
  local -n toks
  if [[ "$side" == A ]]; then
    toks=A_tok
    A_MOVE_KIND=()
    A_MOVE_CHAR=()
    A_MOVE_NEXT=()
    A_MOVE_MODE=()
  else
    toks=B_tok
    B_MOVE_KIND=()
    B_MOVE_CHAR=()
    B_MOVE_NEXT=()
    B_MOVE_MODE=()
  fi
  local n=${#toks[@]}
  if (( idx >= n )); then
    return 0
  fi
  if (( mode == 1 )); then
    add_move "$side" any "" "$idx" 1
    add_move "$side" slash "" "$((idx + 1))" 0
    return 0
  fi
  local t="${toks[$idx]}"
  local kind="${t:0:1}"
  case "$kind" in
    G) add_move "$side" any "" "$idx" 0 ;;
    S) add_move "$side" noslash "" "$idx" 0 ;;
    Q) add_move "$side" noslash "" "$((idx + 1))" 0 ;;
    L)
      local ch="${t:1}"
      if [[ "$ch" == "/" ]]; then
        add_move "$side" slash "" "$((idx + 1))" 0
      else
        add_move "$side" lit "$ch" "$((idx + 1))" 0
      fi
      ;;
    P) ;;
  esac
}

classes_ok() {
  local ak="$1" ac="$2" bk="$3" bc="$4"
  case "$ak:$bk" in
    any:*|*:any) return 0 ;;
    noslash:noslash|slash:slash) return 0 ;;
    noslash:slash|slash:noslash) return 1 ;;
    noslash:lit) [[ "$bc" != "/" ]] ;;
    lit:noslash) [[ "$ac" != "/" ]] ;;
    slash:lit) [[ "$bc" == "/" ]] ;;
    lit:slash) [[ "$ac" == "/" ]] ;;
    lit:lit) [[ "$ac" == "$bc" ]] ;;
    *) return 1 ;;
  esac
}

consume_one() {
  local i=$1 j=$2 ma=$3 mb=$4
  fill_moves A "$i" "$ma"
  fill_moves B "$j" "$mb"
  local -a ak=("${A_MOVE_KIND[@]+"${A_MOVE_KIND[@]}"}")
  local -a ac=("${A_MOVE_CHAR[@]+"${A_MOVE_CHAR[@]}"}")
  local -a an=("${A_MOVE_NEXT[@]+"${A_MOVE_NEXT[@]}"}")
  local -a am=("${A_MOVE_MODE[@]+"${A_MOVE_MODE[@]}"}")
  local -a bk=("${B_MOVE_KIND[@]+"${B_MOVE_KIND[@]}"}")
  local -a bc=("${B_MOVE_CHAR[@]+"${B_MOVE_CHAR[@]}"}")
  local -a bn=("${B_MOVE_NEXT[@]+"${B_MOVE_NEXT[@]}"}")
  local -a bm=("${B_MOVE_MODE[@]+"${B_MOVE_MODE[@]}"}")
  local ai bi
  for (( ai = 0; ai < ${#ak[@]}; ai++ )); do
    for (( bi = 0; bi < ${#bk[@]}; bi++ )); do
      classes_ok "${ak[$ai]}" "${ac[$ai]}" "${bk[$bi]}" "${bc[$bi]}" || continue
      local ni="${an[$ai]}" nj="${bn[$bi]}" nma="${am[$ai]}" nmb="${bm[$bi]}"
      if (( ni == i && nj == j && nma == ma && nmb == mb )); then
        continue
      fi
      if inter "$ni" "$nj" "$nma" "$nmb"; then
        return 0
      fi
    done
  done
  return 1
}

inter() {
  local i=$1 j=$2 ma=$3 mb=$4
  local key="$i,$j,$ma,$mb"
  if [[ -n "${INTER_MEMO[$key]+x}" ]]; then
    if (( INTER_MEMO[$key] == 1 )); then
      return 0
    fi
    return 1
  fi
  if [[ -n "${INTER_VIS[$key]+x}" ]]; then
    return 1
  fi
  INTER_VIS[$key]=1
  local n=${#A_tok[@]} m=${#B_tok[@]}
  local ok=1
  if (( i >= n && j >= m && ma == 0 && mb == 0 )); then
    ok=0
  fi
  if (( ok != 0 && i < n && ma == 0 )); then
    case "${A_tok[$i]}" in
      P)
        inter $((i + 1)) "$j" 0 "$mb" && ok=0
        (( ok != 0 )) && inter "$i" "$j" 1 "$mb" && ok=0
        ;;
      G|S)
        inter $((i + 1)) "$j" 0 "$mb" && ok=0
        ;;
    esac
  fi
  if (( ok != 0 && j < m && mb == 0 )); then
    case "${B_tok[$j]}" in
      P)
        inter "$i" $((j + 1)) "$ma" 0 && ok=0
        (( ok != 0 )) && inter "$i" "$j" "$ma" 1 && ok=0
        ;;
      G|S)
        inter "$i" $((j + 1)) "$ma" 0 && ok=0
        ;;
    esac
  fi
  if (( ok != 0 )); then
    consume_one "$i" "$j" "$ma" "$mb" && ok=0
  fi
  unset "INTER_VIS[$key]"
  if (( ok == 0 )); then
    INTER_MEMO[$key]=1
    return 0
  fi
  INTER_MEMO[$key]=0
  return 1
}

patterns_overlap() {
  compile_tokens "$1" A_tok
  compile_tokens "$2" B_tok
  INTER_MEMO=()
  INTER_VIS=()
  inter 0 0 0 0
}

stream_depends_on() {
  local idx="$1" target="$2"
  local -a deps=()
  split_fields "${DEPS[$idx]:-}" deps
  local dep
  for dep in "${deps[@]+"${deps[@]}"}"; do
    if [[ "$dep" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_commit() {
  local dir="$1" sha="$2"
  git -C "$dir" rev-parse --verify --end-of-options "${sha}^{commit}" 2>/dev/null
}

is_worktree() {
  local dir="$1"
  [[ -d "$dir" ]] || return 1
  [[ "$(git -C "$dir" rev-parse --is-inside-work-tree 2>/dev/null || true)" == "true" ]]
}

is_clean() {
  local dir="$1"
  local out
  if ! out="$(git -C "$dir" status --porcelain --untracked-files=all 2>/dev/null)"; then
    return 2
  fi
  [[ -z "$out" ]]
}

note_dirty() {
  local dirty_msg="$1"
  local unread_msg="$2"
  local dir="$3"
  local rc=0
  is_clean "$dir" || rc=$?
  if (( rc == 2 )); then
    note_fail "$unread_msg"
  elif (( rc != 0 )); then
    note_fail "$dirty_msg"
  fi
}

declare -A EDGE_SET=()
declare -A ADJ=()
declare -A COLOR=()
declare -a STACK=()
CYCLE_MSG=""

add_edge() {
  local from="$1" to="$2"
  local key="${from}"$'\n'"${to}"
  if [[ -n "${EDGE_SET[$key]+x}" ]]; then
    return 0
  fi
  EDGE_SET[$key]=1
  if [[ -z "${ADJ[$from]:-}" ]]; then
    ADJ[$from]="$to"
  else
    ADJ[$from]+=$'\n'"$to"
  fi
}

record_cycle() {
  local back="$1"
  local -a path=()
  local n found=0
  for n in "${STACK[@]}"; do
    if [[ "$n" == "$back" ]]; then
      found=1
    fi
    if (( found )); then
      path+=("$n")
    fi
  done
  path+=("$back")
  local msg="cycle:"
  local first=1
  for n in "${path[@]}"; do
    if (( first )); then
      msg+=" $n"
      first=0
    else
      msg+=" -> $n"
    fi
  done
  CYCLE_MSG="$msg"
}

dfs_cycle() {
  local node="$1"
  COLOR[$node]=1
  STACK+=("$node")
  local -a neighs=()
  split_fields "${ADJ[$node]:-}" neighs
  local neigh c
  for neigh in "${neighs[@]+"${neighs[@]}"}"; do
    c="${COLOR[$neigh]:-0}"
    if [[ "$c" == 1 ]]; then
      record_cycle "$neigh"
      return 0
    fi
    if [[ "$c" == 0 ]]; then
      if dfs_cycle "$neigh"; then
        return 0
      fi
    fi
  done
  unset 'STACK[-1]'
  COLOR[$node]=2
  return 1
}

find_cycle() {
  COLOR=()
  STACK=()
  CYCLE_MSG=""
  local id
  for id in "${IDS[@]}"; do
    if [[ "${COLOR[$id]:-0}" == 0 ]]; then
      if dfs_cycle "$id"; then
        return 0
      fi
    fi
  done
  return 1
}

compile_read_regexes() {
  local idx="$1"
  local -n dest=$2
  dest=()
  local -a reads=()
  split_fields "${READS[$idx]:-}" reads
  local pat re
  for pat in "${reads[@]+"${reads[@]}"}"; do
    re="$(glob_to_ere "$pat")" || return $?
    dest+=("$re")
  done
}

path_matches_any() {
  local path="$1"
  shift
  local re
  for re in "$@"; do
    if [[ "$path" =~ $re ]]; then
      return 0
    fi
  done
  return 1
}

collect_diff_paths() {
  local dir="$1" old="$2" new="$3"
  local -n dest=$4
  dest=()
  local out status path path2
  out="$(mktemp)"
  TMP_FILES+=("$out")
  if ! git -C "$dir" -c core.quotePath=false diff --name-status -z -M -C "${old}..${new}" >"$out"; then
    return 2
  fi
  while IFS= read -r -d '' status; do
    if [[ "$status" =~ ^[RC][0-9]*$ ]]; then
      IFS= read -r -d '' path || return 2
      IFS= read -r -d '' path2 || return 2
      dest+=("$path" "$path2")
    else
      IFS= read -r -d '' path || return 2
      dest+=("$path")
    fi
  done < "$out"
  return 0
}

checkout_binding() {
  # Sets BIND_HEAD, BIND_BRANCH, BIND_RESOLVED. Returns 0 when branch and HEAD match.
  local dir="$1" branch="$2" sha="$3"
  BIND_HEAD=""
  BIND_BRANCH=""
  BIND_RESOLVED=""
  BIND_RESOLVED="$(resolve_commit "$dir" "$sha")" || return 2
  BIND_HEAD="$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null)" || return 1
  if ! BIND_BRANCH="$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)"; then
    BIND_BRANCH="DETACHED"
    return 1
  fi
  [[ "$BIND_HEAD" == "$BIND_RESOLVED" && "$BIND_BRANCH" == "$branch" ]]
}

cmd_ready() {
  RESULT_PREFIX="GRAPH READY"
  parse_spec_file "$spec_file"
  local i j id tid idx
  local -a deps=() writes=() reads=() other_writes=()
  for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    split_fields "${DEPS[$i]:-}" deps
    for tid in "${deps[@]+"${deps[@]}"}"; do
      if [[ -z "${ID_INDEX[$tid]+x}" ]]; then
        note_fail "unknown dependency: $id -> $tid"
        continue
      fi
      idx="${ID_INDEX[$tid]}"
      if [[ "${STATUSES[$idx]}" != "PASS" ]]; then
        local shown="${STATUSES[$idx]}"
        [[ -n "$shown" ]] || shown="missing"
        note_fail "dependency not PASS: $id -> $tid (status: $shown)"
        continue
      fi
      if ! parse_at_sha "${REFS[$idx]}"; then
        note_fail "dependency ref invalid: $tid"
        continue
      fi
      local branch="$AT_LEFT" sha="$AT_SHA"
      if [[ -z "${WORKTREES[$idx]}" ]]; then
        note_fail "dependency ref does not resolve: $tid $sha (missing worktree)"
      elif ! is_worktree "${WORKTREES[$idx]}"; then
        note_fail "dependency ref does not resolve: $tid $sha (worktree unavailable)"
      else
        local bind_rc=0
        checkout_binding "${WORKTREES[$idx]}" "$branch" "$sha" || bind_rc=$?
        if (( bind_rc == 2 )); then
          note_fail "dependency ref does not resolve: $tid $sha"
        elif (( bind_rc != 0 )); then
          note_fail "dependency ref mismatch: $tid expected ${branch}@${sha} got ${BIND_BRANCH}@${BIND_HEAD:-unknown}"
        fi
      fi
      add_edge "$tid" "$id"
    done
  done

  for i in "${!IDS[@]}"; do
    split_fields "${WRITES[$i]:-}" writes
    for (( j = i + 1; j < ${#IDS[@]}; j++ )); do
      split_fields "${WRITES[$j]:-}" other_writes
      local wa wb
      for wa in "${writes[@]+"${writes[@]}"}"; do
        for wb in "${other_writes[@]+"${other_writes[@]}"}"; do
          if patterns_overlap "$wa" "$wb"; then
            note_fail "write/write overlap: ${IDS[$i]} and ${IDS[$j]} ($wa vs $wb)"
          fi
        done
      done
    done
  done

  for i in "${!IDS[@]}"; do
    split_fields "${WRITES[$i]:-}" writes
    for j in "${!IDS[@]}"; do
      (( j != i )) || continue
      split_fields "${READS[$j]:-}" reads
      local wa rb
      for wa in "${writes[@]+"${writes[@]}"}"; do
        for rb in "${reads[@]+"${reads[@]}"}"; do
          if patterns_overlap "$wa" "$rb"; then
            add_edge "${IDS[$i]}" "${IDS[$j]}"
            if ! stream_depends_on "$j" "${IDS[$i]}"; then
              note_fail "read/write overlap without dependency: ${IDS[$j]} reads ${IDS[$i]} ($rb vs $wa)"
            fi
          fi
        done
      done
    done
  done

  if find_cycle; then
    note_fail "$CYCLE_MSG"
  fi
  finish
}

cmd_invalidate() {
  RESULT_PREFIX="GRAPH INVALIDATE"
  parse_spec_file "$spec_file"
  local i id
  for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    if [[ -z "${WORKTREES[$i]}" ]]; then
      note_fail "missing worktree: $id"
      continue
    fi
    if ! is_worktree "${WORKTREES[$i]}"; then
      note_fail "not a work tree: $id ${WORKTREES[$i]}"
      continue
    fi
    if ! parse_at_sha "${REFS[$i]}"; then
      note_fail "invalid ref: $id"
      continue
    fi
    local branch="$AT_LEFT" sha="$AT_SHA"
    note_dirty "dirty worktree: $id" "unreadable status: $id" "${WORKTREES[$i]}"
    local bind_rc=0
    checkout_binding "${WORKTREES[$i]}" "$branch" "$sha" || bind_rc=$?
    if (( bind_rc == 2 )); then
      note_fail "ref does not resolve: $id $sha"
    elif (( bind_rc != 0 )); then
      note_fail "ref mismatch: $id expected ${branch}@${sha} got ${BIND_BRANCH}@${BIND_HEAD:-unknown}"
    fi
  done

  for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    local -a verified=() reads_re=()
    split_fields "${VERIFIED[$i]:-}" verified
    if (( ${#verified[@]} == 0 )); then
      continue
    fi
    compile_read_regexes "$i" reads_re || exit $?
    local entry
    for entry in "${verified[@]}"; do
      if ! parse_at_sha "$entry"; then
        note_fail "stale: $id verified_against invalid ($entry)"
        continue
      fi
      local upstream="$AT_LEFT" old_sha="$AT_SHA"
      if [[ -z "${ID_INDEX[$upstream]+x}" ]]; then
        note_fail "stale: $id verified_against unknown stream $upstream"
        continue
      fi
      local uidx="${ID_INDEX[$upstream]}"
      if [[ -z "${WORKTREES[$uidx]}" ]] || ! is_worktree "${WORKTREES[$uidx]}"; then
        note_fail "stale: $id verified_against $upstream missing worktree"
        continue
      fi
      local resolved_old=""
      if ! resolved_old="$(resolve_commit "${WORKTREES[$uidx]}" "$old_sha")"; then
        note_fail "stale: $id verified_against ${upstream}@${old_sha} missing sha"
        continue
      fi
      local current=""
      if ! current="$(git -C "${WORKTREES[$uidx]}" rev-parse --verify HEAD 2>/dev/null)"; then
        note_fail "stale: $id verified_against $upstream has no HEAD"
        continue
      fi
      local -a changed=()
      local diff_rc=0
      collect_diff_paths "${WORKTREES[$uidx]}" "$resolved_old" "$current" changed || diff_rc=$?
      if (( diff_rc != 0 )); then
        note_fail "stale: $id verified_against ${upstream}@${old_sha} unreadable diff"
        continue
      fi
      local path
      for path in "${changed[@]+"${changed[@]}"}"; do
        if path_matches_any "$path" "${reads_re[@]+"${reads_re[@]}"}"; then
          note_fail "stale: $id verified_against ${upstream}@${old_sha} intersects read via $path"
          break
        fi
      done
    done
  done
  finish
}

cmd_join() {
  RESULT_PREFIX="GRAPH JOIN"
  [[ -n "$integration_ref" ]] || die_usage "--integration-ref is required for join"
  [[ -n "$integration_worktree" ]] || die_usage "--integration-worktree is required for join"
  parse_spec_file "$spec_file"
  if ! parse_at_sha "$integration_ref"; then
    note_fail "integration ref invalid: $integration_ref"
    finish
  fi
  local ibranch="$AT_LEFT" isha="$AT_SHA"
  if ! is_worktree "$integration_worktree"; then
    note_fail "integration checkout unavailable: $integration_worktree"
    finish
  fi
  note_dirty "integration dirty" "integration status unreadable" "$integration_worktree"
  local bind_rc=0
  checkout_binding "$integration_worktree" "$ibranch" "$isha" || bind_rc=$?
  if (( bind_rc == 2 )); then
    note_fail "integration ref does not resolve: $isha"
  elif (( bind_rc != 0 )); then
    note_fail "integration ref mismatch: expected ${ibranch}@${isha} got ${BIND_BRANCH}@${BIND_HEAD:-unknown}"
  fi

  local i id
  for i in "${!IDS[@]}"; do
    id="${IDS[$i]}"
    if [[ "${STATUSES[$i]}" != "PASS" ]]; then
      local shown="${STATUSES[$i]}"
      [[ -n "$shown" ]] || shown="missing"
      note_fail "input not PASS: $id (status: $shown)"
    fi
    if ! parse_at_sha "${REFS[$i]}"; then
      note_fail "input ref invalid: $id"
      continue
    fi
    local branch="$AT_LEFT" sha="$AT_SHA"
    if [[ -z "${WORKTREES[$i]}" ]]; then
      note_fail "input ref does not resolve: $id $sha (missing worktree)"
      continue
    fi
    if ! is_worktree "${WORKTREES[$i]}"; then
      note_fail "input ref does not resolve: $id $sha (worktree unavailable)"
      continue
    fi
    note_dirty "input dirty: $id" "input status unreadable: $id" "${WORKTREES[$i]}"
    bind_rc=0
    checkout_binding "${WORKTREES[$i]}" "$branch" "$sha" || bind_rc=$?
    if (( bind_rc == 2 )); then
      note_fail "input ref does not resolve: $id $sha"
    elif (( bind_rc != 0 )); then
      note_fail "input ref stale: $id expected ${branch}@${sha} got ${BIND_BRANCH}@${BIND_HEAD:-unknown}"
    fi
  done
  finish
}

if [[ $# -lt 1 ]]; then
  die_usage "command is required"
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  ready|invalidate|join)
    cmd="$1"
    shift
    ;;
  *)
    die_usage "unknown command: $1"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || die_usage "--repo requires an argument"
      shift 2
      ;;
    --integration-ref)
      [[ $# -ge 2 ]] || die_usage "--integration-ref requires an argument"
      integration_ref="$2"
      shift 2
      ;;
    --integration-worktree)
      [[ $# -ge 2 ]] || die_usage "--integration-worktree requires an argument"
      integration_worktree="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die_usage "unknown option: $1"
      ;;
    *)
      if [[ -n "$spec_file" ]]; then
        die_usage "unexpected argument: $1"
      fi
      spec_file="$1"
      shift
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  if [[ -n "$spec_file" ]]; then
    die_usage "unexpected argument: $1"
  fi
  spec_file="$1"
  shift
  if [[ $# -gt 0 ]]; then
    die_usage "unexpected argument: $1"
  fi
fi

[[ -n "$spec_file" ]] || die_usage "spec file is required"
if [[ "$cmd" != "join" ]]; then
  if [[ -n "$integration_ref" || -n "$integration_worktree" ]]; then
    die_usage "--integration-ref and --integration-worktree are only valid with join"
  fi
fi

case "$cmd" in
  ready) cmd_ready ;;
  invalidate) cmd_invalidate ;;
  join) cmd_join ;;
esac
