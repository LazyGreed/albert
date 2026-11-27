#!/usr/bin/env bash
# Install Quintet's native agent profiles and skills without replacing user settings.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
harness="pi"
scope="global"
workflow="v2"
target=""
dry=0
with_web=1
tui_mode=auto
explicit_args=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh                       # interactive Pi/Claude Code/Antigravity CLI TUI
       ./install.sh --tui                 # force interactive TUI
       ./install.sh --harness pi|claude|antigravity|codex --scope global|project
                    [--workflow v1|v2] [--target PROJECT_DIR] [--with-web|--no-web]
                    [--dry-run] [--no-tui]

Use arrows and Enter/Space to configure the TUI; preview before installing.
Workflow: v1 sequences coordinator handoffs; v2 (default) uses revision-bound review.
Main-agent personality: PERSONALITY.md beside this repository's AGENTS.md.
Project installs create PROJECT/PERSONALITY.md beside PROJECT/AGENTS.md (never overwrite).
Global: installs in ~/.pi/agent (or PI_CODING_AGENT_DIR), ~/.claude,
~/.gemini/config/plugins/quintet, and/or ${CODEX_HOME:-~/.codex}.
Project: installs in PROJECT/.pi, PROJECT/.claude, or PROJECT/.agents, with
instructions in root AGENTS.md or CLAUDE.md. Codex project agents are
PROJECT/.codex/agents and project skills are in PROJECT/.agents/skills. Global
Codex skills are in ${CODEX_HOME:-~/.codex}/skills. Codex and Pi share PROJECT/AGENTS.md.
The installer preserves Codex config.toml.
Both global and project scopes install the full coordinator contract and personality.
Antigravity installs the quintet plugin (rules/AGENTS.md, worker agents, and skills). A global
install moves an eligible previous plugin tree into ~/.gemini/config/quintet-backups
once the new plugin is written. User rules outside the managed block are carried into
the new file first. Unrecognized entries keep the old plugin in place and are listed.
The installer refuses Antigravity rules over 24000 bytes and checks Codex
AGENTS.md against the default Codex budget of 32768 bytes.
Selecting Pi requires Pi >=1.1.0 and Python 3. The installer validates the pinned
Pi packages and installs absent pins in the Pi agent directory
(PI_CODING_AGENT_DIR or ~/.pi/agent). It creates subagents.json if absent.
Use --no-web to omit web tool grants the installer adds to worker profiles.
Codex uses its own web settings.
--no-web does not skip the Pi package installs. No bundled settings files are copied.
Existing model/provider settings are preserved.
USAGE
}
while (($#)); do
  case "$1" in
    --harness) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; harness="$2"; explicit_args=1; shift 2 ;;
    --scope) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; scope="$2"; explicit_args=1; shift 2 ;;
    --workflow)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      case "$2" in
        v1|v2) workflow="$2" ;;
        *) printf 'Invalid workflow: %s (expected v1 or v2)\n' "$2" >&2; exit 2 ;;
      esac
      explicit_args=1; shift 2 ;;
    --target) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; target="$2"; explicit_args=1; shift 2 ;;
    --with-web) with_web=1; explicit_args=1; shift ;;
    --no-web|--without-web) with_web=0; explicit_args=1; shift ;;
    --dry-run) dry=1; explicit_args=1; shift ;;
    --tui) tui_mode=on; shift ;;
    --no-tui) tui_mode=off; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done
# No-argument terminal invocation opens the TUI. Automation must pass flags.
if [[ "$tui_mode" == on ]] || [[ "$tui_mode" == auto && "$explicit_args" == 0 ]]; then
  if [[ -t 0 && -t 1 ]]; then
    if ((dry)); then echo "TUI already includes a preview; omit --dry-run or use --no-tui for scripted previews." >&2; exit 2; fi
    # A forced TUI uses supplied options as initial selections.
    source "$source_dir/lib/tui.sh"
    quintet_tui
    exit $?
  fi
  if [[ "$tui_mode" == on || "$explicit_args" == 0 ]]; then
    echo 'Interactive install requires a TTY; use --harness ... --scope ... for scripts.' >&2
    exit 2
  fi
fi
[[ "$scope" == global || "$scope" == project ]] || { echo 'Invalid scope' >&2; exit 2; }
IFS=',' read -r -a _harness_list <<< "$harness"
for _h in "${_harness_list[@]}"; do
  case "$_h" in
    pi|claude|antigravity|agy|codex) ;;
    *) echo "Invalid harness: $_h" >&2; exit 2 ;;
  esac
done
if [[ "$scope" == global && -n "$target" ]]; then echo '--target only applies to project installs' >&2; exit 2; fi
if [[ "$scope" == project ]]; then
  target="${target:-$PWD}"
  [[ -d "$target" ]] || { echo "Not a directory: $target" >&2; exit 2; }
  target="$(cd -- "$target" && pwd -P)"
fi

has_harness() { [[ ",$harness," == *",$1,"* ]]; }
report() { printf '%s\n' "$*"; }

# Writes from this invocation. A failed install undoes only these, so a partial
# tree is not left behind and files that already existed are restored.
rb_op=()
rb_a=()
rb_b=()
rollback_armed=1
instruction_refused=0
agy_rule_max_bytes=24000
codex_agents_max_bytes=32768
rule_backup_saved=''
pi_packages=('npm:@tintinweb/pi-subagents@0.26.3' 'npm:pi-web-access@0.48.0')
pi_agent_dir=''
pi_settings_backup=''
note_rollback() {
  rb_op+=("$1")
  rb_a+=("$2")
  rb_b+=("${3-}")
}
note_missing_dirs() {
  local dir="$1" parent i
  local -a missing=()
  parent="$dir"
  while [[ "$parent" != "/" && "$parent" != "." && ! -e "$parent" && ! -L "$parent" ]]; do
    missing+=("$parent")
    parent="$(dirname -- "$parent")"
  done
  for ((i=${#missing[@]}-1; i>=0; i--)); do
    note_rollback create_dir "${missing[i]}"
  done
}
mkparent() {
  local dir
  ((dry)) && return 0
  dir="$(dirname -- "$1")"
  note_missing_dirs "$dir"
  mkdir -p -- "$dir" || return 1
}
rollback_this_run() {
  local i status=0
  ((${#rb_op[@]})) || return 0
  for ((i=${#rb_op[@]}-1; i>=0; i--)); do
    case "${rb_op[i]}" in
      create_file)
        rm -f -- "${rb_a[i]}" || status=1
        ;;
      create_dir)
        if [[ -d "${rb_a[i]}" ]] && ! rmdir -- "${rb_a[i]}" 2>/dev/null; then
          status=1
        fi
        ;;
      replace)
        # cp -p keeps a symlink in place; mv would replace the link with a regular file.
        cp -p -- "${rb_b[i]}" "${rb_a[i]}" && rm -f -- "${rb_b[i]}" || status=1
        ;;
      move)
        rename_only "${rb_b[i]}" "${rb_a[i]}" || status=1
        ;;
      *)
        status=1
        ;;
    esac
  done
  if ((status)); then
    printf 'Install failed and rollback could not restore every file from this run.\n' >&2
  else
    printf 'Install failed; undid writes from this run.\n' >&2
  fi
}
abort_install() {
  local status="${1:-1}"
  trap - ERR
  set +e
  if ((rollback_armed)); then
    rollback_this_run
  fi
  exit "$status"
}

# Never let mv silently switch to copying and unlinking a source across filesystems.
rename_only() {
  if LC_ALL=C mv --help 2>/dev/null | grep -F -- '--no-copy' >/dev/null; then
    mv --no-copy -- "$1" "$2"
  elif command -v python3 >/dev/null; then
    python3 -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$1" "$2"
  elif command -v perl >/dev/null; then
    perl -e 'rename($ARGV[0], $ARGV[1]) or die "rename: $!\n";' -- "$1" "$2"
  else
    printf 'No rename-only archive command available.\n' >&2
    return 1
  fi
}

save_antigravity_rule() {
  local action="$1" rule="$2" backup_root="$3" dir saved
  if ((dry)); then
    report "$action RULE '$rule' under '$backup_root' (dry run)"
    return 0
  fi
  # An install and a legacy carry can both write the same rule in one invocation.
  if [[ -L "$backup_root" || -L "${rule%/*}" ]]; then
    printf 'Cannot create a safe rule backup for %s under %s\n' "$rule" "$backup_root" >&2
    return 1
  fi
  note_missing_dirs "$backup_root"
  if ! mkdir -p -- "$backup_root" || ! dir="$(mktemp -d "$backup_root/rule.XXXXXXXX")"; then
    printf 'Cannot create a safe rule backup for %s under %s\n' "$rule" "$backup_root" >&2
    return 1
  fi
  note_rollback create_dir "$dir"
  saved="$dir/${rule##*/}"
  rule_backup_saved="$saved"
  if [[ "$action" == BACKUP ]] && cp -p -- "$rule" "$saved"; then
    note_rollback create_file "$saved"
  elif [[ "$action" == RELOCATE ]] && rename_only "$rule" "$saved"; then
    note_rollback move "$rule" "$saved"
  else
    rmdir -- "$dir" 2>/dev/null || true
    return 1
  fi
  report "$action RULE '$rule' -> '$saved'"
}

# Never overwrite an existing nonidentical file silently.
put() {
  local src="$1" dst="$2" rule_backups="${3:-}" replaced_from='' backup stamp
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then return 0; fi
  report "WRITE $dst"
  if [[ -n "$rule_backups" && -e "$dst" ]]; then
    save_antigravity_rule BACKUP "$dst" "$rule_backups" || return 1
    replaced_from="$rule_backup_saved"
  fi
  ((dry)) && return 0
  mkparent "$dst" || return 1
  if [[ -z "$rule_backups" && -e "$dst" ]]; then
    # put runs under ||, so a failing date would otherwise leave an empty stamp.
    stamp="$(date +%Y%m%d%H%M%S)" || return 1
    backup="$dst.quintet-backup-${stamp}-$$"
    cp -p -- "$dst" "$backup" || return 1
    replaced_from="$backup"
  fi
  if [[ -n "$replaced_from" ]]; then
    note_rollback replace "$dst" "$replaced_from"
  elif [[ ! -e "$dst" && ! -L "$dst" ]]; then
    note_rollback create_file "$dst"
  fi
  cp -- "$src" "$dst" || return 1
}

# Personality belongs to the main agent; specialist roles are unchanged.
personality_file=''
project_personality=''
coordinator_name=''
coordinator_json_name=''
# Skills shipped to every harness; the migration guard uses the same list as install_skills.
installable_skills=(architecture domain-modeling documentation research verification alien-science-ideation weight-space-network-audit)
resolve_personality() {
  personality_file="$source_dir/PERSONALITY.md"
  if [[ "$scope" == project ]]; then
    project_personality="$target/PERSONALITY.md"
    if [[ -f "$project_personality" ]]; then
      personality_file="$project_personality"
    elif [[ -e "$project_personality" || -L "$project_personality" ]]; then
      echo "Not a regular personality file: $project_personality" >&2
      return 1
    fi
  fi
  local first_line=''
  IFS= read -r first_line < "$personality_file" || true
  if [[ "$first_line" != 'Name: '* ]]; then
    echo "Personality must start with 'Name: Your Name': $personality_file" >&2
    return 1
  fi
  # Read accepts CRLF files; the carriage return is not part of the name.
  first_line="${first_line%$'\r'}"
  coordinator_name="${first_line#Name: }"
  if [[ -z "${coordinator_name//[[:space:]]/}" || ${#coordinator_name} -gt 64 || "$coordinator_name" == *[[:cntrl:]]* ]]; then
    echo "Invalid coordinator name (1-64 printable characters): $personality_file" >&2
    return 1
  fi
  coordinator_json_name="${coordinator_name//\\/\\\\}"
  coordinator_json_name="${coordinator_json_name//\"/\\\"}"
  # Managed markers must not come from user-controlled personality text.
  if ! awk '{
    sub(/\r$/, "")
    if ($0 == "<!-- QUINTET MANAGED START -->" || $0 == "<!-- QUINTET MANAGED END -->" ||
        $0 == "<!-- ALBERT MANAGED START -->" || $0 == "<!-- ALBERT MANAGED END -->") exit 1
  }' "$personality_file"; then
    echo "Reserved managed marker in personality: $personality_file" >&2
    return 1
  fi
}
install_personality() {
  [[ "$scope" == project && ! -f "$project_personality" ]] || return 0
  report "WRITE $project_personality"
  ((dry)) && return 0
  # Create the user-editable project override once. Never overwrite user edits.
  note_rollback create_file "$project_personality"
  cp -- "$source_dir/PERSONALITY.md" "$project_personality" || return 1
  personality_file="$project_personality"
}
render_coordinator() {
  local marker='Source default is [v2](workflows/v2.md). <!-- QUINTET WORKFLOW -->'
  # Skip any managed block and its trailing separator in a self-installed checkout.
  if ! managed_outside_text "$source_dir/AGENTS.md" |
    awk -v marker="$marker" '
      NR == FNR { policy = policy (FNR == 1 ? "#" : "") $0 "\n"; next }
      $0 == "" { blanks++; next }
      { while (blanks > 0) { print ""; blanks-- } }
      $0 == marker { printf "%s", policy; markers++; next }
      { print }
      END { if (markers != 1) exit 1 }
    ' "$source_dir/workflows/$workflow.md" -; then
    echo "Cannot render workflow $workflow from $source_dir/AGENTS.md" >&2
    return 1
  fi
  printf '\n## Main-agent personality (user configuration)\n\n'
  printf 'This section controls only the coordinator name and communication style. Role, permissions, approvals, and verification rules above always take priority.\n\n'
  # awk adds the final newline if absent, and normalizes CRLF to LF.
  # Use this one renderer for both comparison and writing.
  awk '{ sub(/\r$/, ""); print }' "$personality_file"
}

# Both global and project scopes install the full coordinator contract and personality.
render_instructions() {
  render_coordinator
}

role_description() {
  case "$1" in
    nora) printf '%s' 'Read-only investigation, architecture, research, root-cause analysis.' ;;
    felix) printf '%s' 'Implement one bounded code change; perform targeted verification.' ;;
    vera) printf '%s' 'Independent, read-only consequential-change review.' ;;
    iris) printf '%s' 'User-facing end-to-end and smoke acceptance without source edits.' ;;
    *) return 1 ;;
  esac
}

# Generate compact, harness-native subagent frontmatter from a single canonical body.
install_role() {
  local tool="$1" role="$2" dst="$3" tools desc color
  desc="$(role_description "$role")" || return 1
  # Pi badges (widget, FleetView, notifications) tell parallel workers apart at a glance.
  case "$role" in nora) color=cyan ;; felix) color=green ;; vera) color=purple ;; iris) color=orange ;; esac
  if [[ "$tool" == pi ]]; then
    case "$role" in
      felix) tools='read, grep, find, ls, bash, edit, write' ;;
      *) tools='read, grep, find, ls' ;;
    esac
  elif [[ "$tool" == antigravity || "$tool" == agy ]]; then
    if ((with_web)); then
      case "$role" in
        felix) tools='read_file, edit_file, write_file, run_command, manage_task, search_web' ;;
        iris) tools='read_file' ;;
        *) tools='read_file, search_web' ;;
      esac
    else
      case "$role" in
        felix) tools='read_file, edit_file, write_file, run_command, manage_task' ;;
        iris) tools='read_file, run_command, manage_task' ;;
        *) tools='read_file' ;;
      esac
    fi
  else
    case "$role" in
      felix) tools='Read, Grep, Glob, Bash, Edit, Write' ;;
      *) tools='Read, Grep, Glob' ;;
    esac
  fi
  # Expose research tools to the named specialists; Iris remains minimal.
  # Pi extension tools require explicit ext: selectors in tintinweb/pi-subagents.
  if ((with_web)) && [[ "$role" != iris ]]; then
    if [[ "$tool" == pi ]]; then
      tools="$tools, ext:pi-web-access/web_enable, ext:pi-web-access/web_search, ext:pi-web-access/fetch_content, ext:pi-web-access/get_search_content, ext:pi-web-access/source_check"
    elif [[ "$tool" == claude ]]; then
      tools="$tools, WebSearch, WebFetch"
    fi
  fi
  local temp
  temp="$(mktemp)"
  {
    if [[ "$tool" == antigravity || "$tool" == agy ]]; then
      printf -- '---\nname: %s\ndescription: %s\n' "$role" "$desc"
      printf 'subagent: true\nmainAgent: false\n'
      printf 'tools: [%s]\n' "$tools"
      printf -- '---\n\n'
    else
      printf -- '---\nname: %s\ndescription: %s\ntools: %s\n' "$role" "$desc" "$tools"
      if [[ "$tool" == pi ]]; then
        printf 'prompt_mode: append\ncolor: %s\n' "$color"
        if [[ "$role" != felix ]]; then
          if ((with_web)) && [[ "$role" != iris ]]; then
            printf 'extensions: pi-web-access\n'
          else
            printf 'extensions: false\n'
          fi
        fi
      fi
      if [[ "$tool" == claude && "$role" != felix ]]; then
        printf 'disallowedTools: Bash, Write, Edit, NotebookEdit\n'
      fi
      printf -- '---\n\n'
    fi
    cat -- "$source_dir/agents/$role.md"
  } > "$temp" || { rm -f -- "$temp"; return 1; }
  local status=0
  put "$temp" "$dst" || status=$?
  rm -f -- "$temp" || true
  return "$status"
}

# One definition of the managed block and of the user text around it, shared by the
# install merge and the legacy migration.
managed_begin='<!-- QUINTET MANAGED START -->'
managed_end='<!-- QUINTET MANAGED END -->'
old_managed_begin='<!-- ALBERT MANAGED START -->'
old_managed_end='<!-- ALBERT MANAGED END -->'
carry_begin='<!-- QUINTET LEGACY CARRY START -->'
carry_end='<!-- QUINTET LEGACY CARRY END -->'

# Print the user's text only if the managed markers form one ordered pair, or are absent.
managed_outside_text() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  if ! grep -Fqx -e "$managed_begin" -e "$managed_end" -e "$old_managed_begin" -e "$old_managed_end" -- "$src"; then
    cat -- "$src"
  elif ! awk -v b="$managed_begin" -v e="$managed_end" -v ob="$old_managed_begin" -v oe="$old_managed_end" '
    function is_begin() { return $0 == b || $0 == ob }
    function is_end() { return $0 == e || $0 == oe }
    is_begin() { if (state) { bad=1; exit }; state=1; next }
    is_end() { if (state != 1) { bad=1; exit }; state=2; next }
    state != 1 { print }
    END { if (bad || state != 2) exit 1 }
  ' "$src"; then
    echo "Malformed managed markers: $src" >&2
    return 1
  fi
}

# Append text between the managed markers of a file, or nothing when it has none.
# The same extraction feeds both the comparison and the shrink check below.
managed_block_text() {
  local src="$1"
  awk -v b="$managed_begin" -v e="$managed_end" '$0==b {inside=1; next} $0==e {exit} inside {print}' "$src"
}

# Do not add another separator if the existing text already ends with a blank line.
append_block() {
  local dst="$1" body="$2" begin="$3" end="$4"
  if [[ -s "$dst" ]] && [[ "$(tail -c 2 -- "$dst" | od -An -tx1 | tr -d ' \n')" != '0a0a' ]]; then
    printf '\n' >> "$dst" || return 1
  fi
  printf '%s\n' "$begin" >> "$dst" || return 1
  cat -- "$body" >> "$dst" || return 1
  printf '%s\n' "$end" >> "$dst"
}

# Byte cap for a coordinator file this invocation would publish. 0 means no cap.
# Pi and Claude stay uncapped. Pi and Codex share one project AGENTS.md, so that
# file takes the Codex cap when Codex is selected.
instruction_byte_limit() {
  local dst="$1" codex_agents agy_rule
  if has_harness codex; then
    if [[ "$scope" == global ]]; then
      codex_agents="${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
    else
      codex_agents="$target/AGENTS.md"
    fi
    if [[ "$dst" == "$codex_agents" ]]; then
      printf '%s' "$codex_agents_max_bytes"
      return 0
    fi
  fi
  if has_harness antigravity || has_harness agy; then
    if [[ "$scope" == global ]]; then
      agy_rule="$HOME/.gemini/config/plugins/quintet/rules/AGENTS.md"
    else
      agy_rule="$target/.agents/rules/AGENTS.md"
    fi
    if [[ "$dst" == "$agy_rule" ]]; then
      printf '%s' "$agy_rule_max_bytes"
      return 0
    fi
  fi
  printf '%s' 0
}

refuse_oversized() {
  local rendered="$1" dst="$2" limit bytes qualification=''
  limit="$(instruction_byte_limit "$dst")" || return 1
  [[ "$limit" -gt 0 ]] || return 0
  if ! bytes="$(wc -c < "$rendered" | tr -d '[:space:]')" || [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
    printf 'Cannot measure the rendered instructions for %s\n' "$dst" >&2
    instruction_refused=1
    return 1
  fi
  (( bytes <= limit )) && return 0
  if (( limit == codex_agents_max_bytes )); then qualification=' with the default Codex budget'; fi
  instruction_refused=1
  printf 'Cannot publish %s: %s bytes exceeds %s. The harness cannot load this file whole%s.\n' \
    "$dst" "$bytes" "$limit" "$qualification" >&2
  return 1
}

# Preserve the installed bytes when the managed block already matches.
render_instruction_update() {
  local dst="$1" rendered="$2" temp="$3"
  if [[ -f "$dst" ]] && grep -Fqx -- "$managed_begin" "$dst" && grep -Fqx -- "$managed_end" "$dst" &&
    managed_block_text "$dst" | cmp -s "$rendered" -; then
    cp -- "$dst" "$temp"
    return
  fi
  if [[ -f "$dst" ]]; then
    managed_outside_text "$dst" > "$temp" || return 1
  fi
  append_block "$temp" "$rendered" "$managed_begin" "$managed_end"
}

install_instructions() {
  local dst="$1" rule_backups="${2:-}" rendered temp result=0
  rendered="$(mktemp)" || return 1
  if ! temp="$(mktemp)"; then rm -f -- "$rendered"; return 1; fi
  if ! render_instructions > "$rendered" ||
    ! render_instruction_update "$dst" "$rendered" "$temp" ||
    ! refuse_oversized "$temp" "$dst" ||
    ! put "$temp" "$dst" "$rule_backups"; then
    result=1
  fi
  rm -f -- "$temp" "$rendered"
  return "$result"
}

# There is one legacy rules source. Replace its carry block in place; a fenced
# example is user text, not an installer-owned block.
write_carried_rules() {
  local dst="$1" outside="$2" carried="$3" result
  if cmp -s "$outside" "$carried"; then cat -- "$outside" > "$dst"; return; fi
  if awk -v b="$carry_begin" -v e="$carry_end" '
    function fence_line(line, token, ch, suffix) {
      if (!match(line, /^ ? ? ?(```+|~~~+)/)) return 0
      token=substr(line, 1, RLENGTH); suffix=substr(line, RLENGTH+1)
      sub(/^ +/, "", token); ch=substr(token, 1, 1)
      if (fence) {
        if (ch == fence && length(token) >= width && suffix ~ /^[[:space:]]*$/) fence=""
      } else {
        if (ch == "`" && suffix ~ /`/) return 0
        fence=ch; width=length(token)
      }
      return 1
    }
    FILENAME == ARGV[1] { if ($0 == b || $0 == e) { bad=1; exit }; text=text $0 "\n"; next }
    state != 1 && (fence_line($0) || fence) { print; next }
    $0 == b { if (state) { bad=1; exit }; state=1; print b; printf "%s", text; print e; next }
    $0 == e { if (state != 1) { bad=1; exit }; state=2; next }
    state != 1 { print }
    END { if (bad || state == 1 || (!state && fence)) exit 2; if (!state) exit 3 }
  ' "$carried" "$outside" > "$dst"; then
    return 0
  else
    result=$?
    [[ "$result" -eq 3 ]] || return 1
  fi
  if grep -q '[^[:space:]]' "$carried"; then
    append_block "$dst" "$carried" "$carry_begin" "$carry_end"
  fi
}

# The caller reports the planned carry during preview without publishing it.
merge_carried_instructions() {
  local dst="$1" carried="$2" rule_backups="$3" rendered outside temp current="$1" result=0
  rendered="$(mktemp)" || return 2
  if ! outside="$(mktemp)"; then rm -f -- "$rendered"; return 2; fi
  if ! temp="$(mktemp)"; then rm -f -- "$rendered" "$outside"; return 2; fi
  if ((dry)); then current="$temp"; fi
  if ! render_instructions > "$rendered" ||
    { ((dry)) && ! render_instruction_update "$dst" "$rendered" "$temp"; } ||
    ! managed_outside_text "$current" > "$outside" ||
    ! write_carried_rules "$temp" "$outside" "$carried" ||
    ! append_block "$temp" "$rendered" "$managed_begin" "$managed_end" ||
    ! refuse_oversized "$temp" "$dst"; then
    result=1
  elif ((!dry)); then
    put "$temp" "$dst" "$rule_backups" || result=1
  fi
  rm -f -- "$temp" "$outside" "$rendered"
  return "$result"
}

has_old_rule_backup_name() {
  [[ "$2" =~ ^"$1.albert-backup-"[0-9]{14}-[0-9]+$ ]]
}

check_antigravity_rule_backups() {
  local rule="$1" rules_dir="${1%/*}" path candidate
  for path in "${rules_dir%/*}" "$rules_dir"; do
    if [[ -L "$path" || ( -e "$path" && ( ! -d "$path" || ! -r "$path" || ! -x "$path" ) ) ]]; then
      report "KEEP RULE '$path': unsafe or inaccessible path. Inspect it and move old rule backups outside rule discovery before retrying."
      return 1
    fi
  done
  for candidate in "$rule".albert-backup-*; do
    if has_old_rule_backup_name "$rule" "$candidate" &&
      [[ -L "$candidate" || ! -f "$candidate" || ! -r "$candidate" ]]; then
      report "KEEP RULE '$candidate': not a readable regular file without symlinks. Move this entry outside rule discovery manually before retrying."
      return 1
    fi
  done
}

relocate_antigravity_rule_backups() {
  local rule="$1" backup_root="$2" candidate
  check_antigravity_rule_backups "$rule" || return 1
  for candidate in "$rule".albert-backup-*; do
    has_old_rule_backup_name "$rule" "$candidate" || continue
    if [[ ! -w "${rule%/*}" || -L "$backup_root" ||
          ( -e "$backup_root" && ( ! -d "$backup_root" || ! -w "$backup_root" || ! -x "$backup_root" ) ) ||
          ( ! -e "$backup_root" && ! -w "${backup_root%/*}" ) ]] ||
      ! save_antigravity_rule RELOCATE "$candidate" "$backup_root"; then
      report "KEEP RULE '$candidate': cannot move safely to '$backup_root'. Fix the paths or move it outside rule discovery manually before retrying."
      return 1
    fi
  done
}

install_skills() {
  local root="$1" skill file rel
  for skill in "${installable_skills[@]}"; do
    while IFS= read -r -d '' file; do
      rel="${file#"$source_dir"/skills/}"
      put "$file" "$root/skills/$rel" || return 1
    done < <(find "$source_dir/skills/$skill" -type f -print0 | sort -z)
  done
}

# Older installs wrote the Antigravity coordinator to plugins/albert.
# A third-party plugin can use that directory, so the directory name alone cannot
# identify one. Require all four Quintet worker agents and generated text that names Quintet.
legacy_antigravity_plugin() {
  local legacy="$HOME/.gemini/config/plugins/albert" agent workers=0
  [[ -d "$legacy" ]] || return 1
  for agent in nora felix vera iris; do
    if [[ -f "$legacy/agents/$agent.md" ]]; then workers=$((workers + 1)); fi
  done
  [[ "$workers" -eq 4 ]] || return 1
  grep -Fqs -- 'Quintet' "$legacy/agents/albert.md" "$legacy/plugin.json" || return 1
  printf '%s' "$legacy"
}

# A path plus each ancestor, so a directory-only entry is recognised as generated.
_generated_path() {
  local path="$1"
  printf '%s\n' "$path"
  while [[ "$path" == */* ]]; do
    path="${path%/*}"
    printf '%s\n' "$path"
  done
}

# Every relative path a global Antigravity install generates. Compared against a legacy
# tree, so anything else is user content that automatic migration must not destroy.
generated_antigravity_paths() {
  local role skill file rel
  {
    _generated_path plugin.json
    _generated_path rules/AGENTS.md
    # plugins/albert installs include agents/albert.md, so recognize it during migration.
    for role in albert nora felix vera iris; do _generated_path "agents/$role.md"; done
    for skill in "${installable_skills[@]}"; do
      while IFS= read -r -d '' file; do
        rel="${file#"$source_dir"/skills/}"
        _generated_path "skills/$rel"
      done < <(find "$source_dir/skills/$skill" -type f -print0)
    done
  } | sort -u
}

# Archive plugins/albert only after the replacement tree is complete. Generated files
# may also contain user edits, so preserve the entire legacy tree outside plugin discovery.
migrate_legacy_antigravity_plugin() {
  local root="$1" rule_backups="$2" legacy="$3" rel entry list extras=() extra_count=0 total=0 carried carry_status=0
  local backup_root="$HOME/.gemini/config/quintet-backups" backup_dir
  local legacy_rule="$legacy/rules/AGENTS.md" rule="$root/rules/AGENTS.md"
  check_antigravity_rule_backups "$legacy_rule" || return 1
  # Require a complete, non-empty walk before claiming the tree as ours.
  list="$(mktemp)" || return 1
  if ! find "$legacy" -mindepth 1 -print0 > "$list"; then
    rm -f -- "$list"
    report "KEEP '$legacy': the legacy plugin directory could not be enumerated."
    relocate_antigravity_rule_backups "$legacy_rule" "$rule_backups"
    return
  fi
  while IFS= read -r -d '' entry; do
    total=$((total + 1))
    rel="${entry#"$legacy"/}"
    # Preserve any symlink inside the legacy tree rather than unlinking it automatically.
    if [[ -L "$entry" ]] || { ! grep -Fqx -- "$rel" <(generated_antigravity_paths) &&
      ! has_old_rule_backup_name "$legacy_rule" "$entry"; }; then
      extras+=("$rel")
      extra_count=$((extra_count + 1))
    fi
  done < "$list"
  rm -f -- "$list"
  if [[ "$total" -eq 0 ]]; then
    report "KEEP '$legacy': the legacy plugin directory listed no entries."
    return 0
  fi
  if [[ "$extra_count" -eq 0 ]]; then
    # Carry user text out of the managed block before the old tree goes away.
    carried="$(mktemp)" || return 1
    if ! managed_outside_text "$legacy_rule" | awk '{ print }' > "$carried"; then
      rm -f -- "$carried"
      report "KEEP '$legacy': '$legacy_rule' has managed markers that cannot be merged safely."
      relocate_antigravity_rule_backups "$legacy_rule" "$rule_backups"
      return
    fi
    if grep -q '[^[:space:]]' "$carried" ||
      { [[ -f "$rule" ]] && grep -Fqx -e "$carry_begin" -e "$carry_end" -- "$rule"; }; then
      merge_carried_instructions "$rule" "$carried" "$rule_backups" || carry_status=$?
      if (( carry_status )); then
        rm -f -- "$carried"
        if (( instruction_refused || carry_status == 2 )); then return 1; fi
        report "KEEP '$legacy': '$legacy_rule' could not be merged into '$rule'."
        if ((dry)); then return 1; fi
        relocate_antigravity_rule_backups "$legacy_rule" "$rule_backups"
        return
      elif ((dry)); then
        report "CARRY '$legacy_rule' -> '$rule' (dry run; your text outside the managed block would be preserved)"
        report "BACKUP RULE '$rule' under '$rule_backups' (dry run; if carrying rules changes the file)"
      else
        report "CARRY '$legacy_rule' -> '$rule' (your text outside the managed block was preserved)"
      fi
    fi
    rm -f -- "$carried"
    if ((dry)); then
      report "ARCHIVE '$legacy' under '$backup_root' (dry run; preserve the intact legacy plugin)"
      return 0
    elif [[ -L "$backup_root" ]] || ! mkdir -p -- "$backup_root" || ! backup_dir="$(mktemp -d "$backup_root/albert.XXXXXXXX")"; then
      report "KEEP '$legacy': could not create an archive directory under '$backup_root'."
    elif rename_only "$legacy" "$backup_dir/albert"; then
      report "ARCHIVE '$legacy' -> '$backup_dir/albert'"
      return 0
    elif rmdir -- "$backup_dir" 2>/dev/null; then
      report "KEEP '$legacy': could not move the legacy plugin into '$backup_root'."
    else
      report "KEEP '$legacy': the archive move failed and '$backup_dir' could not be removed."
    fi
    relocate_antigravity_rule_backups "$legacy_rule" "$rule_backups"
    return
  fi
  report "KEEP '$legacy': legacy Antigravity plugin kept because it holds entries this installer does not write."
  for entry in "${extras[@]}"; do
    report "  EXTRA '$legacy/$entry'"
  done
  report "  Inspect those entries before moving '$legacy' outside plugin discovery."
  relocate_antigravity_rule_backups "$legacy_rule" "$rule_backups"
}

install_one() {
  local tool="$1" root instruction role rule_backups legacy=''
  if [[ "$tool" == antigravity || "$tool" == agy ]]; then
    if [[ "$scope" == global ]]; then
      root="$HOME/.gemini/config/plugins/quintet"
      rule_backups="$HOME/.gemini/config/quintet-rule-backups"
      if legacy="$(legacy_antigravity_plugin)"; then
        check_antigravity_rule_backups "$legacy/rules/AGENTS.md" || return 1
      fi
    else
      root="$target/.agents"
      rule_backups="$target/.quintet-rule-backups"
    fi
    instruction="$root/rules/AGENTS.md"
    relocate_antigravity_rule_backups "$instruction" "$rule_backups" || return 1
    if [[ "$scope" == global ]]; then
      local manifest="$root/plugin.json"
      local temp_manifest; temp_manifest="$(mktemp)" || return 1
      if ! cat > "$temp_manifest" <<EOF
{
  "name": "quintet",
  "displayName": "$coordinator_json_name",
  "version": "1.0.0",
  "description": "Quintet coordinator with Nora, Felix, Vera, and Iris workers.",
  "suggestedPrompts": [
    "Coordinate implementation and verification for this feature",
    "Investigate root cause and delegate fix to Felix",
    "Run independent review with Vera and smoke test with Iris"
  ]
}
EOF
      then
        rm -f -- "$temp_manifest"
        return 1
      fi
      put "$temp_manifest" "$manifest" || { rm -f -- "$temp_manifest"; return 1; }
      rm -f -- "$temp_manifest"
    fi
    install_instructions "$instruction" "$rule_backups" || return 1
    for role in nora felix vera iris; do
      install_role "$tool" "$role" "$root/agents/$role.md" || return 1
    done
    install_skills "$root" || return 1
    # A successful archive is the last filesystem operation of the install.
    if [[ -n "$legacy" ]]; then
      migrate_legacy_antigravity_plugin "$root" "$rule_backups" "$legacy" || return 1
    fi
    return 0
  fi
  if [[ "$scope" == global ]]; then
    if [[ "$tool" == pi ]]; then root="$pi_agent_dir"; else root="$HOME/.claude"; fi
    if [[ "$tool" == pi ]]; then instruction="$root/AGENTS.md"; else instruction="$root/CLAUDE.md"; fi
  else
    root="$target/.$tool"
    if [[ "$tool" == pi ]]; then instruction="$target/AGENTS.md"; else instruction="$target/CLAUDE.md"; fi
  fi
  install_instructions "$instruction" || return 1
  for role in nora felix vera iris; do
    install_role "$tool" "$role" "$root/agents/$role.md" || return 1
  done
  install_skills "$root" || return 1
  if [[ "$tool" == pi ]]; then install_pi_subagents_config || return 1; fi
}

# Pi installs global package registrations from either scope. Inspect project settings
# separately since an untrusted project is omitted from `pi list --no-approve`.
pi_in_scope() {
  (cd -- "${target:-$HOME}" && NO_COLOR=1 FORCE_COLOR=0 PI_CODING_AGENT_DIR="$pi_agent_dir" pi "$@" --no-approve)
}

pi_missing_packages() {
  local listing project_settings=''
  if ! listing="$(pi_in_scope list)"; then
    echo 'Cannot inspect Pi packages (`pi list --no-approve`).' >&2
    return 1
  fi
  if [[ "$scope" == project ]]; then project_settings="$target/.pi/settings.json"; fi
  python3 - "$pi_agent_dir/settings.json" "$project_settings" "$listing" "${pi_packages[@]}" <<'PY'
import json
import os
from pathlib import Path
import re
import sys

user_settings, project_settings, listing, *pins = sys.argv[1:]
resolved = {}
source = None
for line in listing.splitlines():
    if line.startswith('    ') and source is not None:
        resolved[source] = Path(line[4:])
    elif line.startswith('  '):
        source = re.sub(r' \(filtered\)$', '', line[2:])
    else:
        source = None


def read_json(path):
    with path.open(encoding='utf-8-sig') as stream:
        data = json.load(stream)
    if not isinstance(data, dict):
        raise ValueError(f'expected a JSON object in {path}')
    return data


def registrations(filename, user):
    if not filename:
        return
    path = Path(filename)
    try:
        packages = read_json(path).get('packages', [])
    except FileNotFoundError:
        return
    if not isinstance(packages, list):
        raise ValueError(f'expected an array of packages in {path}')
    for entry in packages:
        source = entry.get('source') if isinstance(entry, dict) else entry
        if not isinstance(source, str) or not source or '\n' in source or '\r' in source:
            raise ValueError(f'invalid package source in {path}')
        npm = re.match(r'^npm:((?:@[^/]+/)?[^@/]+)', source)
        installed = resolved.get(source) if user else None
        if npm and not user:
            installed = path.parent / 'npm' / 'node_modules' / npm[1]
        elif not npm and not installed and not re.match(r'^(git:|https?://|ssh://)', source):
            installed = path.parent / os.path.expanduser(source)
        manifest = None
        if installed is not None:
            module_dir = installed.parent if installed.is_file() else installed
            manifest_path = module_dir / 'package.json'
            try:
                manifest = read_json(manifest_path)
            except (FileNotFoundError, NotADirectoryError):
                pass
        yield path, source, entry, npm[1] if npm else None, manifest


try:
    entries = [*registrations(user_settings, True), *registrations(project_settings, False)]
    missing = []
    for pin in pins:
        name, version = pin[4:].rsplit('@', 1)
        short_name = name.rsplit('/', 1)[-1]
        matches = []
        for path, source, entry, npm_name, manifest in entries:
            basename = re.split(r'[@#]', Path(source.rstrip('/')).name, maxsplit=1)[0]
            alternate = not npm_name and basename in (short_name, f'{short_name}.git')
            alias = npm_name and re.search(r'@npm:' + re.escape(name) + r'(?:@|$)', source)
            if npm_name == name or (manifest or {}).get('name') == name or alternate or alias:
                matches.append((path, source, entry, manifest))
        if not matches:
            missing.append(pin)
        elif len(matches) > 1:
            locations = ', '.join(f'{source} in {path}' for path, source, _, _ in matches)
            raise ValueError(f'ambiguous registrations for {pin}: {locations}')
        else:
            path, source, entry, manifest = matches[0]
            if source != pin or isinstance(entry, dict) and set(entry) != {'source'}:
                raise ValueError(f'{source} in {path} needs an unfiltered exact {pin} registration')
            if not manifest or (manifest.get('name'), manifest.get('version')) != (name, version):
                actual = f"{manifest.get('name')}@{manifest.get('version')}" if manifest else 'missing package manifest'
                raise ValueError(f'{pin} in {path} resolves to {actual}. Repair that installation before retrying.')
    print('\n'.join(missing))
except (OSError, ValueError) as error:
    sys.exit(f'Cannot inspect Pi packages: {error}')
PY
}

protect_pi_settings() {
  local settings="$pi_agent_dir/settings.json"
  if [[ -L "$settings" || ( -e "$settings" && ! -f "$settings" ) ]]; then
    printf 'Cannot safely register Pi packages in %s\n' "$settings" >&2
    return 1
  fi
  if [[ -f "$settings" ]]; then
    pi_settings_backup="$(mktemp)" || return 1
    if ! cp -p -- "$settings" "$pi_settings_backup"; then
      rm -f -- "$pi_settings_backup"
      return 1
    fi
    note_rollback replace "$settings" "$pi_settings_backup"
  else
    note_rollback create_file "$settings"
  fi
}

install_pi_runtime() {
  local spec missing version
  pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  if [[ "$pi_agent_dir" == '~/'* ]]; then pi_agent_dir="$HOME/${pi_agent_dir:2}"; fi
  if [[ "$pi_agent_dir" != /* ]]; then pi_agent_dir="$PWD/$pi_agent_dir"; fi
  if ((dry)); then
    report 'CHECK Pi >=1.1.0 before install'
    for spec in "${pi_packages[@]}"; do report "INSTALL IF ABSENT: pi install $spec --no-approve"; done
    return 0
  fi
  command -v pi >/dev/null || { echo 'Pi missing. Install Pi >=1.1.0 first.' >&2; return 1; }
  command -v python3 >/dev/null || { echo 'Python 3 is required to inspect Pi packages.' >&2; return 1; }
  version="$(pi --version 2>/dev/null)" || { echo 'Cannot check Pi version.' >&2; return 1; }
  if [[ ! "$version" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    printf 'Cannot parse Pi version: %s\n' "$version" >&2; return 1
  fi
  if (( 10#${BASH_REMATCH[1]} < 1 || (10#${BASH_REMATCH[1]} == 1 && 10#${BASH_REMATCH[2]} < 1) )); then
    printf 'Pi >=1.1.0 required (found %s).\n' "$version" >&2; return 1
  fi
  missing="$(pi_missing_packages)" || return 1
  for spec in "${pi_packages[@]}"; do
    if ! grep -Fxq -- "$spec" <<< "$missing"; then
      report "SKIP PI PACKAGE: $spec is already registered; unchanged."
    fi
  done
  [[ -n "$missing" ]] || return 0
  protect_pi_settings || return 1
  while IFS= read -r spec; do
    report "INSTALL: pi install $spec --no-approve"
    pi_in_scope install "$spec" || return 1
  done <<< "$missing"
  missing="$(pi_missing_packages)" || return 1
  if [[ -n "$missing" ]]; then
    printf 'Pi did not register required packages:\n%s\n' "$missing" >&2
    return 1
  fi
}
install_pi_subagents_config() {
  local dst="$pi_agent_dir/subagents.json" temp
  if [[ -e "$dst" || -L "$dst" ]]; then
    [[ -f "$dst" ]] || { printf 'Not a regular Pi subagent config: %s\n' "$dst" >&2; return 1; }
    return 0
  fi
  temp="$(mktemp)" || return 1
  cat > "$temp" <<'EOF'
{
  "maxSubagentDepth": 1,
  "defaultJoinMode": "group",
  "disableDefaultAgents": true,
  "packageAgents": false,
  "fallbackSubagent": "none",
  "fleetView": false,
  "widgetMode": "all"
}
EOF
  put "$temp" "$dst" || { rm -f -- "$temp"; return 1; }
  rm -f -- "$temp"
}

# Codex agents are standalone TOML. A literal body cannot contain '''.
codex_agents_embeddable() {
  local role body status
  for role in nora felix vera iris; do
    body="$source_dir/agents/$role.md"
    if ! cat -- "$body" >/dev/null; then
      printf 'Cannot read agent body: %s\n' "$body" >&2
      return 1
    fi
    status=0
    grep -Fq "'''" -- "$body" || status=$?
    if (( status > 1 )); then
      printf 'Cannot read agent body: %s\n' "$body" >&2
      return 1
    fi
    if (( status == 0 )); then
      printf 'Cannot install Codex agent %s: agent body contains a TOML literal delimiter.\n' "$role" >&2
      return 1
    fi
  done
}

toml_basic_string() {
  local value="$1" escaped
  escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '"%s"' "$escaped"
}

install_codex_role() {
  local role="$1" dst="$2" desc body temp status=0
  desc="$(role_description "$role")" || return 1
  body="$source_dir/agents/$role.md"
  temp="$(mktemp)" || return 1
  {
    printf 'name = %s\n' "$(toml_basic_string "$role")" || status=1
    printf 'description = %s\n' "$(toml_basic_string "$desc")" || status=1
    printf "developer_instructions = '''\n" || status=1
    cat -- "$body" || status=1
    printf "'''\n" || status=1
    if [[ "$role" != felix ]]; then
      printf '\n[features]\nshell_tool = false\nrequest_permissions_tool = false\n' || status=1
    fi
  } > "$temp" || status=1
  if (( status != 0 )); then
    rm -f -- "$temp"
    return 1
  fi
  put "$temp" "$dst" || status=$?
  rm -f -- "$temp"
  return "$status"
}

install_codex() {
  local root instruction skills_root role
  if [[ "$scope" == global ]]; then
    root="${CODEX_HOME:-$HOME/.codex}"
    instruction="$root/AGENTS.md"
    skills_root="$root"
  else
    root="$target/.codex"
    instruction="$target/AGENTS.md"
    skills_root="$target/.agents"
  fi
  codex_agents_embeddable || return 1
  install_instructions "$instruction" || return 1
  for role in nora felix vera iris; do
    install_codex_role "$role" "$root/agents/$role.toml" || return 1
  done
  install_skills "$skills_root"
}

trap 'abort_install $?' ERR
resolve_personality || abort_install $?
report "WORKFLOW $workflow"
if has_harness pi; then install_pi_runtime || abort_install $?; fi
install_personality || abort_install $?
if has_harness pi; then install_one pi || abort_install $?; fi
if has_harness claude; then install_one claude || abort_install $?; fi
if has_harness codex; then install_codex || abort_install $?; fi
# Antigravity can archive a legacy plugin after completing all install writes.
if has_harness antigravity || has_harness agy; then install_one antigravity || abort_install $?; fi
# Summary lines are not part of the tree. Do not undo a finished install if one fails.
rollback_armed=0
if [[ -n "$pi_settings_backup" ]]; then rm -f -- "$pi_settings_backup"; fi

if ((with_web)) && { has_harness pi || has_harness claude || has_harness antigravity || has_harness agy; }; then
  report 'WEB: added worker tool grants for Nora/Felix/Vera. Runtime access depends on the harness and provider configuration.'
fi
report 'MODELS: choose per-agent model/effort; model and provider settings unchanged.'
report 'DONE'
