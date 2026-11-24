#!/usr/bin/env bash
# Install Quintet's native agent profiles and skills without replacing user settings.
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
harness="pi"
scope="global"
target=""
dry=0
with_jev=0
with_web=1
tui_mode=auto
explicit_args=0

usage() {
  cat <<'USAGE'
Usage: ./install.sh                       # interactive TUI
       ./install.sh --tui                 # force interactive TUI
       ./install.sh --harness pi|claude|antigravity|pi,claude,antigravity --scope global|project
                    [--target PROJECT_DIR] [--with-jev] [--with-web|--no-web] [--dry-run] [--no-tui]

Use arrows and Enter/Space to configure the TUI; preview before installing.
Main-agent personality: PERSONALITY.md beside this repository's AGENTS.md.
Project installs create PROJECT/PERSONALITY.md beside PROJECT/AGENTS.md (never overwrite).
Global: installs in ~/.pi/agent, ~/.claude, and/or ~/.gemini/config/plugins/albert; project: in PROJECT/.pi,
PROJECT/.claude, and/or PROJECT/.agents plus an Albert block in root AGENTS.md/CLAUDE.md.
Web research is enabled by default for eligible workers (use --no-web to disable).
No change to existing model/provider settings. Jev remains opt-in.
USAGE
}
while (($#)); do
  case "$1" in
    --harness) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; harness="$2"; explicit_args=1; shift 2 ;;
    --scope) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; scope="$2"; explicit_args=1; shift 2 ;;
    --target) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; target="$2"; explicit_args=1; shift 2 ;;
    --with-jev) with_jev=1; explicit_args=1; shift ;;
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
    # A forced TUI takes supplied harness/scope/jev options as initial selections.
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
# Preflight optional dependencies before changing any target files.
if ((with_jev)); then
  [[ -f "$source_dir/extensions/k-jev/package.json" ]] || { echo 'k-jev source missing' >&2; exit 1; }
  if (( !dry )); then
    command -v npm >/dev/null || { echo 'npm required for --with-jev' >&2; exit 1; }
  fi
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
  if ((with_jev)) && [[ "$role" == nora || "$role" == vera ]]; then
    if [[ "$tool" == pi ]]; then
      tools="$tools, jev_evaluate, jev_search, jev_evaluate_files, jev_evaluate_diff"
    else
      tools="$tools, mcp__k-jev__jev_evaluate, mcp__k-jev__jev_search, mcp__k-jev__jev_evaluate_files, mcp__k-jev__jev_evaluate_diff"
    fi
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
      if [[ "$role" == albert ]]; then
        printf 'mainAgent: true\nsubagent: true\n'
      else
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

# Add/update only our clearly delimited section. Never discard project instructions.
install_instructions() {
  local dst="$1" begin='<!-- ALBERT MANAGED START -->' end='<!-- ALBERT MANAGED END -->'
  if [[ -f "$dst" ]] && grep -Fqx "$begin" "$dst" && grep -Fqx "$end" "$dst"; then
    if awk -v b="$begin" -v e="$end" '$0==b {inside=1; next} $0==e {exit} inside {print}' "$dst" | cmp -s <(render_coordinator) -; then
      return 0
    fi
  fi
  local temp; temp="$(mktemp)"
  if [[ -f "$dst" ]]; then
    if grep -Fqx "$begin" "$dst"; then
      if ! grep -Fqx "$end" "$dst"; then
        echo "Malformed Albert markers: $dst" >&2; rm -f "$temp"; return 1
      fi
      awk -v b="$begin" -v e="$end" '$0==b {skip=1; next} $0==e {skip=0; next} !skip {print}' "$dst" > "$temp"
    else
      cp -- "$dst" "$temp"
    fi
  fi
  { printf '\n%s\n' "$begin"; render_coordinator; printf '%s\n' "$end"; } >> "$temp"
  put "$temp" "$dst"
  rm -f -- "$temp"
}

install_one() {
  local tool="$1" root instruction
  if [[ "$tool" == antigravity || "$tool" == agy ]]; then
    if [[ "$scope" == global ]]; then
      root="$HOME/.gemini/config/plugins/albert"
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
  "name": "albert",
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
    for skill in architecture domain-modeling ui-ux documentation research verification alien-science-ideation weight-space-network-audit; do
      while IFS= read -r -d '' file; do
        rel="${file#"$source_dir"/skills/}"
        put "$file" "$root/skills/$rel"
      done < <(find "$source_dir/skills/$skill" -type f -print0 | sort -z)
    done
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
  for skill in architecture domain-modeling ui-ux documentation research verification alien-science-ideation weight-space-network-audit; do
    while IFS= read -r -d '' file; do
      rel="${file#"$source_dir"/skills/}"
      put "$file" "$root/skills/$rel"
    done < <(find "$source_dir/skills/$skill" -type f -print0 | sort -z)
  done
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
pi_jev_registered() {
  local packages file pi_root files=()
  if [[ -n "${PI_CODING_AGENT_DIR:-}" ]]; then
    pi_root="$PI_CODING_AGENT_DIR"
  elif [[ -n "${HOME:-}" ]]; then
    pi_root="$HOME/.pi/agent"
  else
    pi_root=""
  fi
  [[ -n "$pi_root" ]] && files+=("$pi_root/settings.json")
  [[ "$scope" != project ]] || files+=("$target/.pi/settings.json")
  packages="$(pi_in_scope list 2>/dev/null)" || packages=''
  grep -Fq 'k-jev' <<< "$packages" && return 0
  for file in "${files[@]+"${files[@]}"}"; do
    [[ -f "$file" ]] && grep -Fq 'k-jev' "$file" && return 0
  done
  return 1
}

# Install only on explicit opt-in, and reuse any already registered Pi package.
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

if ((with_jev)); then
  jev="$source_dir/extensions/k-jev"
  [[ -f "$jev/package.json" ]] || { echo 'k-jev source missing' >&2; exit 1; }
  report "JEV OPT-IN $jev"
  if (( !dry )); then
    command -v npm >/dev/null || { echo 'npm required for --with-jev' >&2; exit 1; }
    (cd "$jev" && npm ci --ignore-scripts && npm run build)
  fi
  if has_harness pi; then
    if ((dry)); then report "CHECK Pi Jev registration; install only if absent: $jev"
    elif pi_jev_registered; then report 'SKIP PI JEV: registration exists; unchanged.'
    elif [[ "$scope" == project ]]; then (cd "$target" && pi install -l "$jev")
    else pi install "$jev"; fi
  fi
  if has_harness claude; then
    if ((dry)); then report "CHECK claude mcp get k-jev; add only if absent (scope $([[ "$scope" == global ]] && echo user || echo project))";
    elif command -v claude >/dev/null; then
      # Preserve existing registrations (including those from another scope).
      # A registered MCP server must not be replaced as a side effect of installation.
      if [[ "$scope" == project ]]; then
        if (cd "$target" && claude mcp get k-jev >/dev/null 2>&1); then
          report 'SKIP CLAUDE MCP: k-jev already registered; existing configuration preserved.'
        else
          (cd "$target" && claude mcp add --scope project --transport stdio k-jev -- node "$jev/dist/mcp.js")
        fi
      else
        if claude mcp get k-jev >/dev/null 2>&1; then
          report 'SKIP CLAUDE MCP: k-jev already registered; existing configuration preserved.'
        else
          claude mcp add --scope user --transport stdio k-jev -- node "$jev/dist/mcp.js"
        fi
      fi
    else report 'MANUAL: install Claude Code and register the k-jev MCP server'; fi
  fi
  report 'Jev requires K_JEV_BASE_URL, K_JEV_MODEL, and K_JEV_API_KEY at runtime.'
fi

if has_harness pi; then
  report 'OPTIONAL (Pi): one notification per parallel batch needs "defaultJoinMode": "group" in subagents.json; not set here. See docs/workflow.md.'
fi
if ((with_web)); then
  report 'WEB: enabled for the coordinator and Nora/Felix/Vera; verify runtime access and provider configuration. Iris unchanged.'
fi
report 'MODELS: choose per-agent model/effort; user settings untouched.'
report 'DONE'
