#!/usr/bin/env bash
# Install Quintet's native agent profiles and skills without replacing user settings.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
harness="pi"
scope="global"
target=""
dry=0
with_web=1
tui_mode=auto
explicit_args=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh                       # interactive Pi/Claude Code TUI
       ./install.sh --tui                 # force interactive TUI
       ./install.sh --harness pi|claude|antigravity|pi,claude,antigravity --scope global|project
                    [--target PROJECT_DIR] [--with-web|--no-web] [--dry-run] [--no-tui]

Use arrows and Enter/Space to configure the TUI; preview before installing.
Main-agent personality: PERSONALITY.md beside this repository's AGENTS.md.
Project installs create PROJECT/PERSONALITY.md beside PROJECT/AGENTS.md (never overwrite).
Global: installs in ~/.pi/agent (or PI_CODING_AGENT_DIR), ~/.claude, and/or
~/.gemini/config/plugins/quintet. Project: installs in PROJECT/.pi or PROJECT/.claude
with instructions in root AGENTS.md or CLAUDE.md, or in PROJECT/.agents for Antigravity.
Antigravity names the coordinator agent quintet in both scopes. A global install replaces a
legacy ~/.gemini/config/plugins/albert (the previous project name) once the new plugin is
written: text you added to its rules/AGENTS.md outside the managed block is carried into the
new file first. An entry this installer does not write keeps the old directory and is listed.
Web research is enabled by default for eligible workers (use --no-web to disable).
No bundled settings files are copied. Existing model/provider settings are preserved.
USAGE
}
while (($#)); do
  case "$1" in
    --harness) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; harness="$2"; explicit_args=1; shift 2 ;;
    --scope) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; scope="$2"; explicit_args=1; shift 2 ;;
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
    # A forced TUI takes supplied harness, scope, target, and web options as initial selections.
    source "$source_dir/lib/tui.sh"
    albert_tui
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
    pi|claude|antigravity|agy) ;;
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
mkparent() { if (( !dry )); then mkdir -p -- "$(dirname -- "$1")"; fi; }
# Never overwrite an existing nonidentical file silently.
put() {
  local src="$1" dst="$2"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then return; fi
  report "WRITE $dst"
  ((dry)) && return 0
  mkparent "$dst"
  if [[ -e "$dst" ]]; then
    cp -p -- "$dst" "$dst.albert-backup-$(date +%Y%m%d%H%M%S)-$$"
  fi
  cp -- "$src" "$dst"
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
    if ($0 == "<!-- ALBERT MANAGED START -->" || $0 == "<!-- ALBERT MANAGED END -->") exit 1
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
  cp -- "$source_dir/PERSONALITY.md" "$project_personality"
  personality_file="$project_personality"
}
render_coordinator() {
  cat -- "$source_dir/AGENTS.md"
  printf '\n## Main-agent personality (user configuration)\n\n'
  printf 'This section controls only the coordinator name and communication style. Role, permissions, approvals, and verification rules above always take priority.\n\n'
  # awk adds the final newline if absent, and normalizes CRLF to LF.
  # Use this one renderer for both comparison and writing.
  awk '{ sub(/\r$/, ""); print }' "$personality_file"
}

# Generate compact, harness-native subagent frontmatter from a single canonical body.
install_role() {
  local tool="$1" role="$2" dst="$3" tools desc color
  case "$role" in
    albert) desc='Quintet coordinator; delegates to Nora/Felix/Vera/Iris, verifies, and reports.' ;;
    nora) desc='Read-only investigation, architecture, research, root-cause analysis.' ;;
    felix) desc='Implement one bounded code change; perform targeted verification.' ;;
    vera) desc='Independent, read-only consequential-change review.' ;;
    iris) desc='User-facing end-to-end and smoke acceptance without source edits.' ;;
    *) return 1 ;;
  esac
  # Pi badges (widget, FleetView, notifications) tell parallel workers apart at a glance.
  case "$role" in nora) color=cyan ;; felix) color=green ;; vera) color=purple ;; iris) color=orange ;; esac
  if [[ "$tool" == pi ]]; then
    case "$role" in
      felix) tools='read, grep, find, ls, bash, edit, write' ;;
      *) tools='read, grep, find, ls, bash' ;;
    esac
  elif [[ "$tool" == antigravity || "$tool" == agy ]]; then
    if ((with_web)); then
      case "$role" in
        albert) tools='read_file, run_command, manage_task, search_web, invoke_subagent, send_message, manage_subagents, ask_question' ;;
        felix) tools='read_file, edit_file, write_file, run_command, manage_task, search_web' ;;
        iris) tools='read_file, run_command, manage_task' ;;
        *) tools='read_file, run_command, manage_task, search_web' ;;
      esac
    else
      case "$role" in
        albert) tools='read_file, run_command, manage_task, invoke_subagent, send_message, manage_subagents, ask_question' ;;
        felix) tools='read_file, edit_file, write_file, run_command, manage_task' ;;
        iris) tools='read_file, run_command, manage_task' ;;
        *) tools='read_file, run_command, manage_task' ;;
      esac
    fi
  else
    case "$role" in
      felix) tools='Read, Grep, Glob, Bash, Edit, Write' ;;
      *) tools='Read, Grep, Glob, Bash' ;;
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
      # Antigravity exposes the agent name to the user, so the coordinator is Quintet.
      # Other harnesses keep the internal `albert` agent key their installs depend on.
      if [[ "$role" == albert ]]; then
        printf -- '---\nname: quintet\ndescription: %s\n' "$desc"
        printf 'mainAgent: true\nsubagent: true\n'
      else
        printf -- '---\nname: %s\ndescription: %s\n' "$role" "$desc"
        printf 'subagent: true\nmainAgent: false\n'
      fi
      printf 'tools: [%s]\n' "$tools"
      printf -- '---\n\n'
    else
      printf -- '---\nname: %s\ndescription: %s\ntools: %s\n' "$role" "$desc" "$tools"
      if [[ "$tool" == pi ]]; then printf 'prompt_mode: append\ncolor: %s\n' "$color"; fi
      if [[ "$tool" == claude && "$role" != felix ]]; then printf 'disallowedTools: Write, Edit, NotebookEdit\n'; fi
      if [[ "$tool" == pi && "$role" != felix ]]; then printf 'disallowed_tools: edit, write\n'; fi
      printf -- '---\n\n'
    fi
    if [[ "$role" == albert ]]; then
      render_coordinator
    else
      cat -- "$source_dir/agents/$role.md"
    fi
  } > "$temp"
  put "$temp" "$dst"
  rm -f -- "$temp"
}

# One definition of the managed block and of the user text around it, shared by the
# install merge and the legacy migration.
managed_begin='<!-- ALBERT MANAGED START -->'
managed_end='<!-- ALBERT MANAGED END -->'

# Print a file with the managed block and its markers removed, i.e. the user's own text.
# Fails when the markers cannot be merged safely, so callers never drop text silently.
managed_outside_text() {
  local src="$1"
  [[ -e "$src" ]] || return 0
  if grep -Fqx -- "$managed_begin" "$src"; then
    if ! grep -Fqx -- "$managed_end" "$src"; then
      echo "Malformed Albert markers: $src" >&2
      return 1
    fi
    awk -v b="$managed_begin" -v e="$managed_end" '$0==b {skip=1; next} $0==e {skip=0; next} !skip {print}' "$src"
  else
    cat -- "$src"
  fi
}

# Add/update only our clearly delimited section. Never discard project instructions.
install_instructions() {
  local dst="$1"
  if [[ -f "$dst" ]] && grep -Fqx -- "$managed_begin" "$dst" && grep -Fqx -- "$managed_end" "$dst"; then
    if awk -v b="$managed_begin" -v e="$managed_end" '$0==b {inside=1; next} $0==e {exit} inside {print}' "$dst" | cmp -s <(render_coordinator) -; then
      return 0
    fi
  fi
  local temp; temp="$(mktemp)"
  if [[ -f "$dst" ]]; then
    if ! managed_outside_text "$dst" > "$temp"; then rm -f -- "$temp"; return 1; fi
  fi
  { printf '\n%s\n' "$managed_begin"; render_coordinator; printf '%s\n' "$managed_end"; } >> "$temp"
  put "$temp" "$dst"
  rm -f -- "$temp"
}

# Fold text carried from a legacy tree into freshly written instructions, keeping the same
# "user text outside the managed block" contract as install_instructions.
merge_carried_instructions() {
  local dst="$1" carried="$2" temp
  temp="$(mktemp)"
  if ! managed_outside_text "$dst" > "$temp"; then rm -f -- "$temp"; return 1; fi
  cat -- "$carried" >> "$temp"
  { printf '\n%s\n' "$managed_begin"; render_coordinator; printf '%s\n' "$managed_end"; } >> "$temp"
  put "$temp" "$dst"
  rm -f -- "$temp"
}

install_skills() {
  local root="$1" skill file rel
  for skill in "${installable_skills[@]}"; do
    while IFS= read -r -d '' file; do
      rel="${file#"$source_dir"/skills/}"
      put "$file" "$root/skills/$rel"
    done < <(find "$source_dir/skills/$skill" -type f -print0 | sort -z)
  done
}

# Older Quintet installs wrote the Antigravity coordinator to plugins/albert; Albert was the
# project's previous name. Only a tree this project generates is ours: a third-party plugin
# may also be called Albert, so a bare name or a coordinator file cannot identify one.
# Require all four Quintet worker agents and generated text that names Quintet.
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
    for role in albert nora felix vera iris; do _generated_path "agents/$role.md"; done
    for skill in "${installable_skills[@]}"; do
      while IFS= read -r -d '' file; do
        rel="${file#"$source_dir"/skills/}"
        _generated_path "skills/$rel"
      done < <(find "$source_dir/skills/$skill" -type f -print0)
    done
  } | sort -u
}

# Count entries under a directory. Fails when the walk itself fails, so a caller never reads
# "could not look" as "nothing there".
count_entries() {
  local dir="$1" list total=0 entry
  list="$(mktemp)"
  if ! find "$dir" -mindepth 1 -print0 > "$list"; then rm -f -- "$list"; return 1; fi
  while IFS= read -r -d '' entry; do total=$((total + 1)); done < "$list"
  rm -f -- "$list"
  printf '%s' "$total"
}

# Replace plugins/albert after the new tree is complete. Runs last so a failed or partial
# install never leaves the user without a coordinator, and never fails the install.
migrate_legacy_antigravity_plugin() {
  local root="$1" legacy rel entry list extras=() extra_count=0 total=0 carried remaining removed
  legacy="$(legacy_antigravity_plugin)" || return 0
  # Deletion needs a complete, non-empty walk: a failed or empty enumeration is not evidence
  # that the tree is safe to remove.
  list="$(mktemp)"
  if ! find "$legacy" -mindepth 1 -print0 > "$list"; then
    rm -f -- "$list"
    report "KEEP '$legacy': the legacy plugin directory could not be enumerated, so nothing was removed."
    return 0
  fi
  while IFS= read -r -d '' entry; do
    total=$((total + 1))
    rel="${entry#"$legacy"/}"
    # rm -rf unlinks a symlink itself; data behind the link is never touched, so a link is
    # not user content that blocks migration.
    [[ -L "$legacy/$rel" ]] && continue
    if ! grep -Fqx -- "$rel" <(generated_antigravity_paths); then
      extras+=("$rel")
      extra_count=$((extra_count + 1))
    fi
  done < "$list"
  rm -f -- "$list"
  if [[ "$total" -eq 0 ]]; then
    report "KEEP '$legacy': the legacy plugin directory listed no entries, so nothing was removed."
    return 0
  fi
  if [[ "$extra_count" -eq 0 ]]; then
    # Carry user text out of the managed block before the old tree goes away.
    if [[ -f "$legacy/rules/AGENTS.md" ]]; then
      carried="$(mktemp)"
      if ! managed_outside_text "$legacy/rules/AGENTS.md" > "$carried"; then
        rm -f -- "$carried"
        report "KEEP '$legacy': '$legacy/rules/AGENTS.md' has managed markers that cannot be merged safely, so nothing was removed."
        return 0
      fi
      if grep -q '[^[:space:]]' "$carried"; then
        if ((dry)); then
          report "CARRY '$legacy/rules/AGENTS.md' -> '$root/rules/AGENTS.md' (dry run; your text outside the managed block would be preserved)"
        elif ! merge_carried_instructions "$root/rules/AGENTS.md" "$carried"; then
          rm -f -- "$carried"
          report "KEEP '$legacy': '$legacy/rules/AGENTS.md' could not be merged into '$root/rules/AGENTS.md', so nothing was removed."
          return 0
        else
          report "CARRY '$legacy/rules/AGENTS.md' -> '$root/rules/AGENTS.md' (your text outside the managed block was preserved)"
        fi
      fi
      rm -f -- "$carried"
    fi
    if ((dry)); then
      report "REMOVE '$legacy' (dry run; legacy Antigravity plugin: every entry is a path this installer rewrites on each update and would be recreated at '$root')"
    elif rm -rf -- "$legacy"; then
      report "REMOVE '$legacy' (legacy Antigravity plugin, previous project name: every entry is a path this installer rewrites on each update, and the current versions are at '$root')"
    else
      # rm failed midway: report what actually remains instead of claiming nothing changed.
      if [[ ! -e "$legacy" ]]; then
        report "REMOVE '$legacy' (legacy Antigravity plugin, previous project name: removed, with the current versions at '$root')"
      elif remaining="$(count_entries "$legacy")"; then
        removed=$((total - remaining))
        ((removed < 0)) && removed=0
        report "KEEP '$legacy': automatic removal failed partway; $removed of $total entries were removed and $remaining remain. Inspect it and remove it yourself: rm -rf -- '$legacy'"
      else
        report "KEEP '$legacy': automatic removal failed and the remaining entries could not be counted. Inspect it and remove it yourself: rm -rf -- '$legacy'"
      fi
    fi
    return 0
  fi
  report "KEEP '$legacy': legacy Antigravity plugin kept because it holds entries this installer does not write."
  for entry in "${extras[@]}"; do
    report "  EXTRA '$legacy/$entry'"
  done
  report "  Inspect or back up those entries, then remove the directory yourself if you accept losing them: rm -rf -- '$legacy'"
  return 0
}

install_one() {
  local tool="$1" root instruction role
  if [[ "$tool" == antigravity || "$tool" == agy ]]; then
    if [[ "$scope" == global ]]; then
      root="$HOME/.gemini/config/plugins/quintet"
      instruction="$root/rules/AGENTS.md"
    else
      root="$target/.agents"
      instruction="$root/rules/AGENTS.md"
    fi
    if [[ "$scope" == global ]]; then
      local manifest="$root/plugin.json"
      local temp_manifest; temp_manifest="$(mktemp)"
      cat > "$temp_manifest" <<EOF
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
      put "$temp_manifest" "$manifest"
      rm -f -- "$temp_manifest"
    fi
    install_instructions "$instruction"
    for role in albert nora felix vera iris; do install_role "$tool" "$role" "$root/agents/$role.md"; done
    install_skills "$root"
    # Migrate only after the replacement tree is fully written and verified above.
    if [[ "$scope" == global ]]; then migrate_legacy_antigravity_plugin "$root"; fi
    return
  fi
  if [[ "$scope" == global ]]; then
    if [[ "$tool" == pi ]]; then root="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"; else root="$HOME/.claude"; fi
    if [[ "$tool" == pi ]]; then instruction="$root/AGENTS.md"; else instruction="$root/CLAUDE.md"; fi
  else
    root="$target/.$tool"
    if [[ "$tool" == pi ]]; then instruction="$target/AGENTS.md"; else instruction="$target/CLAUDE.md"; fi
  fi
  install_instructions "$instruction"
  for role in nora felix vera iris; do install_role "$tool" "$role" "$root/agents/$role.md"; done
  install_skills "$root"
}

# Verify the native Pi dependency before touching user files. Preview stays offline.
pi_in_scope() {
  if [[ "$scope" == project ]]; then (cd "$target" && pi "$@");
  else (cd "$HOME" && pi "$@"); fi
}
pi_preflight() {
  ((dry)) && { report 'CHECK Pi >=1.1.0 and npm:@tintinweb/pi-subagents before install'; return 0; }
  command -v pi >/dev/null || { echo 'Pi missing. Install Pi >=1.1.0 first.' >&2; return 1; }
  local version
  version="$(pi --version 2>/dev/null)" || { echo 'Cannot check Pi version.' >&2; return 1; }
  if [[ ! "$version" =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
    printf 'Cannot parse Pi version: %s\n' "$version" >&2; return 1
  fi
  if (( 10#${BASH_REMATCH[1]} < 1 || (10#${BASH_REMATCH[1]} == 1 && 10#${BASH_REMATCH[2]} < 1) )); then
    printf 'Pi >=1.1.0 required (found %s).\n' "$version" >&2; return 1
  fi
  local packages
  packages="$(pi_in_scope list 2>/dev/null)" || { echo 'Cannot inspect Pi packages (`pi list`).' >&2; return 1; }
  if ! grep -Fq '@tintinweb/pi-subagents' <<< "$packages"; then
    echo 'Missing tintinweb agents. Run: pi install npm:@tintinweb/pi-subagents' >&2
    return 1
  fi
}

# Install only when web access is enabled, and reuse any already registered Pi package.
# Preflight runs first, before changing target files or package settings.
pi_web_registered() {
  local packages
  packages="$(pi_in_scope list 2>/dev/null)" || { echo 'Cannot inspect Pi packages (`pi list`).' >&2; return 2; }
  grep -Eq '(^|[^[:alnum:]_-])pi-web-access([^[:alnum:]_-]|$)' <<< "$packages"
}
install_pi_web() {
  if ((dry)); then
    report 'CHECK Pi web: install npm:pi-web-access only if absent'
  elif pi_web_registered; then
    report 'SKIP PI WEB: pi-web-access is already registered; unchanged.'
  elif [[ "$scope" == project ]]; then
    pi_in_scope install -l npm:pi-web-access
  else
    pi_in_scope install npm:pi-web-access
  fi
}

resolve_personality
if has_harness pi; then pi_preflight; fi
install_personality
if ((with_web)) && has_harness pi; then install_pi_web; fi
has_harness pi && install_one pi
has_harness claude && install_one claude
(has_harness antigravity || has_harness agy) && install_one antigravity

if has_harness pi; then
  report 'OPTIONAL (Pi): one notification per parallel batch needs "defaultJoinMode": "group" in subagents.json; not set here. See docs/workflow.md.'
fi
if ((with_web)); then
  report 'WEB: enabled for the coordinator and Nora/Felix/Vera; verify runtime access and provider configuration. Iris unchanged.'
fi
report 'MODELS: choose per-agent model/effort; model and provider settings unchanged.'
report 'DONE'
