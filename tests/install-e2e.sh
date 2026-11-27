#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
# A negative grep must fail on a match even under set -e.
assert_absent() {
  local pattern="$1" file="$2" status
  if grep -q -- "$pattern" "$file"; then
    printf 'Unexpected match (%s) in %s\n' "$pattern" "$file" >&2
    exit 1
  else
    status=$?
    if ((status != 1)); then
      printf 'Cannot check %s (grep exit %d)\n' "$file" "$status" >&2
      exit 1
    fi
  fi
}
assert_workflow() {
  local edition="$1" file="$2"
  [[ "$(grep -Ec '^## Workflow v[12]$' "$file")" -eq 1 ]]
  grep -Fqx "## Workflow $edition" "$file"
  assert_absent 'QUINTET WORKFLOW\|workflows/v[12]\.md' "$file"
  if [[ "$edition" == v1 ]]; then
    grep -Fq 'sequences work using' "$file"
    assert_absent 'VERIFIED_AGAINST\|INTEGRATION_REF' "$file"
  else
    grep -Fq 'VERIFIED_AGAINST' "$file"
    grep -Fq 'INTEGRATION_REF' "$file"
    assert_absent 'sequences work using' "$file"
  fi
  [[ "$(grep -Fxc '<!-- QUINTET MANAGED START -->' "$file")" -eq 1 ]]
  [[ "$(grep -Fxc '<!-- QUINTET MANAGED END -->' "$file")" -eq 1 ]]
  assert_absent '<!-- ALBERT MANAGED' "$file"
}
# Weight-audit references ship byte-for-byte. Enumerate the source tree so a new
# reference cannot be silently skipped; a missing installed copy fails the cmp.
assert_refs() {
  local dest="$1" ref
  for ref in "$root"/skills/weight-space-network-audit/references/*.md; do
    cmp -- "$ref" "$dest/${ref##*/}"
  done
}
# Byte-stable listing of files, directories, and links under a tree.
# A failed install must match the snapshot taken before it ran.
snapshot_tree() {
  local dir="$1" out="$2" path crc size
  : > "$out"
  while IFS= read -r -d '' path; do
    if [[ -L "$dir/$path" ]]; then
      printf 'link %s %s\n' "$path" "$(readlink -- "$dir/$path")"
    elif [[ -f "$dir/$path" ]]; then
      read -r crc size _ < <(cksum -- "$dir/$path")
      printf 'file %s %s %s\n' "$crc" "$size" "$path"
    elif [[ -d "$dir/$path" ]]; then
      printf 'dir %s\n' "$path"
    else
      printf 'other %s\n' "$path"
    fi
  done < <(cd -- "$dir" && find . -print0 | sort -z) >> "$out"
}
# Byte-exact text before the managed block, so blank lines there are compared too.
prefix_bytes() {
  local file="$1" offset
  offset="$(grep -b -m1 -F -e '<!-- QUINTET MANAGED START -->' -e '<!-- ALBERT MANAGED START -->' "$file" | head -n1 | cut -d: -f1)"
  head -c "$offset" -- "$file"
}
project="$tmp/kanade"
mkdir -p "$project" "$tmp/bin"
printf '# Kanade contract\nKeep this rule.\n' > "$project/AGENTS.md"
printf '# Claude contract\nKeep this too.\n' > "$project/CLAUDE.md"
cat > "$tmp/bin/pi" <<'PI'
#!/usr/bin/env bash
if [[ -n "${MOCK_PI_CALLS:-}" ]]; then printf '%s\n' "$*" >> "$MOCK_PI_CALLS"; fi
case "$1" in
  --version) printf 'pi %s\n' "${MOCK_PI_VERSION:-1.1.0}" ;;
  list)
    [[ "${MOCK_PI_LIST_STATUS:-0}" == 0 ]] || exit "$MOCK_PI_LIST_STATUS"
    printf '%s\n' "${MOCK_PI_PACKAGES:-npm:@tintinweb/pi-subagents}"
    ;;
  install)
    printf 'pi %s\n' "$*" >> "$MOCK_PI_LOG"
    if [[ -n "${MOCK_PI_INSTALL_FAIL:-}" && "$2" == "$MOCK_PI_INSTALL_FAIL" ]]; then exit 1; fi
    ;;
  *) exit 1 ;;
esac
PI
chmod +x "$tmp/bin/pi"
export PATH="$tmp/bin:$PATH" MOCK_PI_LOG="$tmp/pi-actions" MOCK_PI_CALLS="$tmp/pi-calls" MOCK_PI_VERSION=1.1.0
export MOCK_PI_PACKAGES=$'npm:@tintinweb/pi-subagents\nnpm:pi-web-access'
both_pi_packages="$MOCK_PI_PACKAGES"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" PI_CODING_AGENT_DIR="$tmp/home/.pi/agent"
mkdir -p "$HOME"

# Validate before the TUI, Pi preflight, or any project writes. A later valid flag
# must not mask an earlier invalid value.
for bad_workflow in '' v3 ../v1; do
  rc=0
  "$root/install.sh" --tui --harness pi,claude,antigravity --scope project --target "$project" \
    --workflow "$bad_workflow" --workflow v2 > "$tmp/invalid-workflow" 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]]
  grep -Fq 'Invalid workflow:' "$tmp/invalid-workflow"
  assert_absent '^WRITE ' "$tmp/invalid-workflow"
  [[ ! -e "$project/PERSONALITY.md" && ! -e "$project/.agents" && ! -e "$MOCK_PI_LOG" ]]
done

"$root/install.sh" --help > "$tmp/help"
assert_absent '[Aa]lbert' "$tmp/help"
"$root/install.sh" --harness pi,claude --scope project --target "$project" --dry-run > "$tmp/dry"
[[ ! -d "$project/.pi" && ! -d "$project/.claude" && ! -e "$project/PERSONALITY.md" ]]
[[ ! -e "$PI_CODING_AGENT_DIR/subagents.json" && ! -e "$MOCK_PI_LOG" && ! -e "$MOCK_PI_CALLS" ]]
grep -Fxq 'CHECK Pi >=1.1.0 before install' "$tmp/dry"
grep -Fxq 'INSTALL IF ABSENT: pi install npm:@tintinweb/pi-subagents' "$tmp/dry"
grep -Fxq 'INSTALL IF ABSENT: pi install npm:pi-web-access' "$tmp/dry"
grep -Fxq "WRITE $PI_CODING_AGENT_DIR/subagents.json" "$tmp/dry"
"$root/install.sh" --harness claude --scope project --target "$project" --dry-run > "$tmp/claude-dry"
assert_absent 'pi install\|subagents.json' "$tmp/claude-dry"
MOCK_PI_VERSION=0.87.1 "$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/version" 2>&1 && exit 1
! test -d "$project/.pi"
[[ ! -e "$PI_CODING_AGENT_DIR/subagents.json" && ! -e "$project/PERSONALITY.md" ]]
grep -q 'Pi >=1.1.0 required' "$tmp/version"
PATH="/usr/bin:/bin" "$root/install.sh" --harness pi --scope project --target "$project" > "$tmp/no-pi" 2>&1 && exit 1
[[ ! -e "$project/.pi" && ! -e "$PI_CODING_AGENT_DIR/subagents.json" && ! -e "$project/PERSONALITY.md" ]]
grep -q 'Pi missing. Install Pi >=1.1.0 first.' "$tmp/no-pi"
MOCK_PI_LIST_STATUS=1 "$root/install.sh" --harness pi --scope project --target "$project" > "$tmp/list-fail" 2>&1 && exit 1
unset MOCK_PI_LIST_STATUS
[[ ! -e "$project/.pi" && ! -e "$PI_CODING_AGENT_DIR/subagents.json" ]]
grep -q 'Cannot inspect Pi packages' "$tmp/list-fail"
[[ ! -s "$MOCK_PI_LOG" ]]

# Missing packages are installed with the exact global commands, including project scope and --no-web.
# A package already shown by pi list is not installed again. Claude-only installs do not run pi.
pkg_home="$tmp/pkg-home"
pkg_project="$tmp/pkg-project"
mkdir -p "$pkg_home" "$pkg_project"
cat > "$tmp/expected-subagents.json" <<'JSON'
{
  "maxSubagentDepth": 1,
  "defaultJoinMode": "group",
  "disableDefaultAgents": true,
  "packageAgents": false,
  "fallbackSubagent": "none",
  "fleetView": false,
  "widgetMode": "all"
}
JSON
: > "$MOCK_PI_LOG"
MOCK_PI_PACKAGES='npm:unrelated' HOME="$pkg_home" PI_CODING_AGENT_DIR="$pkg_home/.pi/agent" \
  "$root/install.sh" --harness pi --scope project --target "$pkg_project" --no-web > "$tmp/pkg-install"
grep -Fxq 'pi install npm:@tintinweb/pi-subagents' "$MOCK_PI_LOG"
grep -Fxq 'pi install npm:pi-web-access' "$MOCK_PI_LOG"
grep -Fxq 'INSTALL: pi install npm:@tintinweb/pi-subagents' "$tmp/pkg-install"
grep -Fxq 'INSTALL: pi install npm:pi-web-access' "$tmp/pkg-install"
assert_absent 'install -l\|pi install -l' "$MOCK_PI_LOG"
[[ "$(grep -c '^pi install ' "$MOCK_PI_LOG")" -eq 2 ]]
assert_absent 'pi-web-access/' "$pkg_project/.pi/agents/nora.md"
[[ ! -e "$pkg_project/.pi/subagents.json" ]]
cmp -- "$tmp/expected-subagents.json" "$pkg_home/.pi/agent/subagents.json"
[[ "$(tail -c 1 "$pkg_home/.pi/agent/subagents.json" | od -An -tx1 | tr -d ' ')" == 0a ]]
printf '{ "defaultJoinMode": "wait", "extra": true }\n' > "$pkg_home/.pi/agent/subagents.json"
: > "$MOCK_PI_LOG"
MOCK_PI_PACKAGES="$both_pi_packages" HOME="$pkg_home" PI_CODING_AGENT_DIR="$pkg_home/.pi/agent" \
  "$root/install.sh" --harness pi --scope global --no-web > "$tmp/pkg-replace"
assert_absent '^pi install ' "$MOCK_PI_LOG"
grep -Fq 'SKIP PI PACKAGE: npm:@tintinweb/pi-subagents is already registered; unchanged.' "$tmp/pkg-replace"
grep -Fq 'SKIP PI PACKAGE: npm:pi-web-access is already registered; unchanged.' "$tmp/pkg-replace"
cmp -- "$tmp/expected-subagents.json" "$pkg_home/.pi/agent/subagents.json"
assert_absent 'wait' "$pkg_home/.pi/agent/subagents.json"
claude_only="$tmp/claude-only-home"
mkdir -p "$claude_only"
: > "$MOCK_PI_CALLS"
HOME="$claude_only" PI_CODING_AGENT_DIR="$claude_only/.pi/agent" \
  "$root/install.sh" --harness claude --scope global > "$tmp/claude-only"
[[ ! -e "$claude_only/.pi/agent/subagents.json" && ! -s "$MOCK_PI_CALLS" ]]
agy_only="$tmp/agy-only-home"
mkdir -p "$agy_only"
: > "$MOCK_PI_CALLS"
HOME="$agy_only" PI_CODING_AGENT_DIR="$agy_only/.pi/agent" \
  "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-only"
[[ ! -e "$agy_only/.pi/agent/subagents.json" && ! -s "$MOCK_PI_CALLS" ]]
MOCK_PI_PACKAGES="$both_pi_packages"

"$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/initial"
[[ -f "$project/PERSONALITY.md" && ! -d "$project/.quintet" ]]
cmp -s "$root/PERSONALITY.md" "$project/PERSONALITY.md"
[[ -f "$project/.pi/agents/felix.md" && -f "$project/.claude/agents/vera.md" ]]
[[ ! -e "$project/.pi/skills/ui-ux" ]]
[[ ! -e "$project/.claude/skills/ui-ux" ]]
[[ -f "$project/.pi/skills/verification/SKILL.md" ]]
[[ -f "$project/.claude/skills/verification/SKILL.md" ]]
[[ -x "$project/.pi/skills/verification/scripts/check-ownership.sh" ]]
[[ -x "$project/.claude/skills/verification/scripts/check-ownership.sh" ]]
[[ -x "$project/.pi/skills/verification/scripts/check-readonly.sh" ]]
[[ -x "$project/.claude/skills/verification/scripts/check-readonly.sh" ]]
grep -q 'regression check' "$project/.pi/skills/verification/SKILL.md"
grep -q 'vertical slice' "$project/.claude/skills/verification/SKILL.md"
# Alien Science Ideation stays installed. Profiles prove it is opt-in: the skill
# is present, and coordinator instructions do not apply it unless the user asks.
for tool in pi claude; do
  cmp -s "$root/skills/alien-science-ideation/SKILL.md" "$project/.$tool/skills/alien-science-ideation/SKILL.md"
  grep -q '^name: alien-science-ideation$' "$project/.$tool/skills/alien-science-ideation/SKILL.md"
  cmp -s "$root/skills/alien-science-ideation/references/discovery-workflow.md" "$project/.$tool/skills/alien-science-ideation/references/discovery-workflow.md"
  grep -q 'opt-in' "$project/.$tool/skills/alien-science-ideation/SKILL.md"
  assert_absent 'Always-on' "$project/.$tool/skills/alien-science-ideation/SKILL.md"
  cmp -s "$root/skills/weight-space-network-audit/SKILL.md" "$project/.$tool/skills/weight-space-network-audit/SKILL.md"
  assert_refs "$project/.$tool/skills/weight-space-network-audit/references"
  for role in nora felix vera iris; do
    assert_absent 'Alien Science Ideation is always on' "$project/.$tool/agents/$role.md"
    assert_absent 'Always-on Alien Science' "$project/.$tool/agents/$role.md"
  done
done
for file in "$project/AGENTS.md" "$project/CLAUDE.md"; do
  assert_workflow v2 "$file"
  grep -q '^## Opt-in Alien Science Ideation$' "$file"
  grep -q '^## Dispatch$' "$file"
  grep -q '^## Delegation gate$' "$file"
  grep -q '^## Reporting$' "$file"
  grep -q '^## Main-agent personality (user configuration)$' "$file"
  assert_absent 'Alien Science Ideation is always on' "$file"
  assert_absent 'Always-on Alien Science' "$file"
done
weight_skill="$project/.pi/skills/weight-space-network-audit/SKILL.md"
assert_absent 'without further instructions, treat it as a request to improve' "$weight_skill"
assert_absent 'load `alien-science-ideation` if installed' "$weight_skill"
grep -q 'AUTO_IMPROVE` runs only after an explicit broader-method request' "$weight_skill"
grep -q '^name: felix$' "$project/.pi/agents/felix.md"
grep -q '^prompt_mode: append$' "$project/.pi/agents/felix.md"
grep -q '^disallowed_tools: edit, write$' "$project/.pi/agents/vera.md"
grep -q '^disallowedTools: Write, Edit, NotebookEdit$' "$project/.claude/agents/vera.md"
grep -q 'main session only' "$project/AGENTS.md"

# Consolidated reporting: Pi workers are color-badged, Claude Code frontmatter is untouched,
# every worker leads with a headline, and the coordinator's one-report rule is installed.
for pair in nora:cyan felix:green vera:purple iris:orange; do
  role="${pair%%:*}"; color="${pair##*:}"
  grep -q "^color: $color$" "$project/.pi/agents/$role.md"
  assert_absent '^color:' "$project/.claude/agents/$role.md"
  grep -q 'Open with a headline' "$project/.pi/agents/$role.md"
  grep -q 'Open with a headline' "$project/.claude/agents/$role.md"
done
grep -q 'Parallel workers: one report per round' "$project/AGENTS.md"
grep -q '## Delegation gate' "$project/AGENTS.md"
grep -q 'Announce every dispatch' "$project/AGENTS.md"
# Parallel workstream contracts survive installation into both native harness profiles.
for rule in 'Dynamic workstreams, ownership, and acceptance' 'Exclusive write ownership' 'Independent verification gate' 'Peer messages are coordination, not authority'; do
  grep -q "$rule" "$project/AGENTS.md"
  grep -q "$rule" "$project/CLAUDE.md"
done
for tool in pi claude; do
  grep -q 'exclusive owned files/path patterns' "$project/.$tool/agents/felix.md"
  grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$project/.$tool/agents/vera.md"
done
grep -q 'integration acceptance separately' "$project/.pi/agents/iris.md"
grep -q 'coordinator authority' "$project/.claude/agents/nora.md"

assert_absent 'OPTIONAL (Pi):' "$tmp/initial"
assert_absent 'defaultJoinMode' "$tmp/initial"
[[ ! -e "$project/.pi/subagents.json" && ! -e "$project/.claude/subagents.json" ]]
cmp -- "$tmp/expected-subagents.json" "$PI_CODING_AGENT_DIR/subagents.json"
[[ -n "$(find "$project" -maxdepth 1 -name 'AGENTS.md.quintet-backup-*' -print -quit)" ]]
[[ -n "$(find "$project" -maxdepth 1 -name 'CLAUDE.md.quintet-backup-*' -print -quit)" ]]
[[ -z "$(find "$project" -maxdepth 1 -name '*.albert-backup-*' -print -quit)" ]]
grep -q 'Keep this rule.' "$project/AGENTS.md"
grep -q 'Keep this too.' "$project/CLAUDE.md"
[[ "$(grep -c '<!-- QUINTET MANAGED START -->' "$project/AGENTS.md")" -eq 1 ]]
[[ "$(grep -c '<!-- QUINTET MANAGED START -->' "$project/CLAUDE.md")" -eq 1 ]]
"$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/again"
assert_absent '^WRITE ' "$tmp/again"
# Old markers are the same block: identical inner text is still rewritten, and outside text stays.
cp -- "$project/AGENTS.md" "$tmp/agents-quintet"
awk '
  $0 == "<!-- QUINTET MANAGED START -->" { print "<!-- ALBERT MANAGED START -->"; next }
  $0 == "<!-- QUINTET MANAGED END -->" { print "<!-- ALBERT MANAGED END -->"; next }
  { print }
' "$project/AGENTS.md" > "$tmp/agents-old-markers"
cp -- "$tmp/agents-old-markers" "$project/AGENTS.md"
"$root/install.sh" --harness pi --scope project --target "$project" > "$tmp/marker-rewrite"
grep -Fxq "WRITE $project/AGENTS.md" "$tmp/marker-rewrite"
[[ "$(grep -c '^WRITE ' "$tmp/marker-rewrite")" -eq 1 ]]
cmp -- "$tmp/agents-quintet" "$project/AGENTS.md"
grep -Fxq 'Keep this rule.' "$project/AGENTS.md"

# No bundled settings or legacy package install on a fresh install in either scope.
[[ ! -e "$project/.claude/settings.json" && ! -e "$project/.pi/settings.json" ]]
"$root/install.sh" --harness pi,claude --scope global > "$tmp/global"
[[ -f "$HOME/.claude/CLAUDE.md" && -f "$PI_CODING_AGENT_DIR/agents/felix.md" ]]
[[ ! -e "$HOME/.claude/settings.json" && ! -e "$PI_CODING_AGENT_DIR/settings.json" ]]
[[ ! -e "$PI_CODING_AGENT_DIR/pi-blackhole" && ! -e "$project/.pi/pi-blackhole" ]]
assert_absent 'pi-blackhole' "$MOCK_PI_LOG"
[[ ! -e "$project/.mcp.json" && ! -e "$HOME/.claude.json" ]]

# Global scope installs the full coordinator contract and personality while preserving
# user text outside the managed markers (including upgrading a prior policy-only block).
for file in "$PI_CODING_AGENT_DIR/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
  grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$file"
  grep -q '^## Dispatch$' "$file"
  grep -q '^## Delegation gate$' "$file"
  grep -q '^## Opt-in Alien Science Ideation$' "$file"
  grep -q '^## Main-agent personality' "$file"
  assert_absent 'cross-project policy' "$file"
  assert_absent 'Alien Science Ideation is always on' "$file"
  assert_absent 'Always-on Alien Science' "$file"
done

# Both scopes re-install as exact no-ops; the global files stay byte-identical.
cp "$PI_CODING_AGENT_DIR/AGENTS.md" "$tmp/global-pi-once"
cp "$HOME/.claude/CLAUDE.md" "$tmp/global-claude-once"
for attempt in 1 2; do
  "$root/install.sh" --harness pi,claude --scope global > "$tmp/global-again-$attempt"
  assert_absent '^WRITE ' "$tmp/global-again-$attempt"
  assert_absent '^SHRINK ' "$tmp/global-again-$attempt"
  cmp "$tmp/global-pi-once" "$PI_CODING_AGENT_DIR/AGENTS.md"
  cmp "$tmp/global-claude-once" "$HOME/.claude/CLAUDE.md"
done

# Upgrading a global file with a managed block preserves every byte outside the markers,
# including blank-line layout, while leaving sibling files alone.
upgrade_home="$tmp/upgrade-home"
upgrade_agents="$upgrade_home/.pi/agent/AGENTS.md"
run_upgrade_install() {
  HOME="$upgrade_home" XDG_CONFIG_HOME="$upgrade_home/.config" PI_CODING_AGENT_DIR="$upgrade_home/.pi/agent" \
    "$root/install.sh" --harness pi --scope global "$@"
}
seed_old_global() {
  {
    printf "$1"
    printf '<!-- ALBERT MANAGED START -->\n# Quintet | cross-project policy\n<!-- ALBERT MANAGED END -->\n'
  } > "$upgrade_agents"
}
mkdir -p "$upgrade_home/.pi/agent"
printf '{ "model" : "user-owned" }\n' > "$upgrade_home/.pi/agent/settings.json"
cp "$upgrade_home/.pi/agent/settings.json" "$tmp/upgrade-settings"
seed_old_global '\n# Machine notes\nKeep my global note.\n\n'
prefix_bytes "$upgrade_agents" > "$tmp/upgrade-prefix-before"
run_upgrade_install > "$tmp/upgrade"
grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$upgrade_agents"
grep -q '^## Dispatch$' "$upgrade_agents"
grep -q '^## Main-agent personality' "$upgrade_agents"
assert_absent 'cross-project policy' "$upgrade_agents"
[[ "$(grep -Fxc '<!-- QUINTET MANAGED START -->' "$upgrade_agents")" -eq 1 ]]
assert_absent '<!-- ALBERT MANAGED' "$upgrade_agents"
prefix_bytes "$upgrade_agents" > "$tmp/upgrade-prefix-after"
cmp "$tmp/upgrade-prefix-before" "$tmp/upgrade-prefix-after"
grep -Fqx 'Keep my global note.' "$upgrade_agents"
cmp "$tmp/upgrade-settings" "$upgrade_home/.pi/agent/settings.json"
cp "$upgrade_agents" "$tmp/upgrade-once"
run_upgrade_install > "$tmp/upgrade-again"
assert_absent '^WRITE ' "$tmp/upgrade-again"
cmp "$tmp/upgrade-once" "$upgrade_agents"

# Upgrading from a file whose only outside text is blank lines keeps them byte-for-byte.
seed_old_global '\n\n'
prefix_bytes "$upgrade_agents" | od -An -c > "$tmp/upgrade-blank-before"
run_upgrade_install > "$tmp/upgrade-blank"
prefix_bytes "$upgrade_agents" | od -An -c > "$tmp/upgrade-blank-after"
cmp "$tmp/upgrade-blank-before" "$tmp/upgrade-blank-after"
grep -q '^## Dispatch$' "$upgrade_agents"

# Normal reinstalls must not replace unrelated settings or erase user-managed legacy config.
printf '{ "model" : "user-owned" }\n\n' > "$tmp/claude-settings"
cp "$tmp/claude-settings" "$project/.claude/settings.json"
cp "$tmp/claude-settings" "$tmp/linked-settings"
ln -s "$tmp/linked-settings" "$HOME/.claude/settings.json"
printf '{ "packages" : ["npm:pi-blackhole", "npm:other"] }\n\n' > "$tmp/pi-settings"
cp "$tmp/pi-settings" "$project/.pi/settings.json"
cp "$tmp/pi-settings" "$PI_CODING_AGENT_DIR/settings.json"
printf '{ "mcpServers" : { "user-tool" : { "command" : "user-tool" } } }\n' > "$tmp/mcp-registration"
cp "$tmp/mcp-registration" "$project/.mcp.json"
cp "$tmp/mcp-registration" "$HOME/.claude.json"
printf '{ "compactionEngine" : "blackhole" }\n\n' > "$tmp/legacy-blackhole"
mkdir -p "$PI_CODING_AGENT_DIR/pi-blackhole"
cp "$tmp/legacy-blackhole" "$PI_CODING_AGENT_DIR/pi-blackhole/pi-blackhole-config.json"
"$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/preserve-project"
"$root/install.sh" --harness pi,claude --scope global > "$tmp/preserve-global"
cmp "$tmp/claude-settings" "$project/.claude/settings.json"
[[ "$(readlink "$HOME/.claude/settings.json")" == "$tmp/linked-settings" ]]
cmp "$tmp/claude-settings" "$HOME/.claude/settings.json"
cmp "$tmp/pi-settings" "$project/.pi/settings.json"
cmp "$tmp/pi-settings" "$PI_CODING_AGENT_DIR/settings.json"
cmp "$tmp/legacy-blackhole" "$PI_CODING_AGENT_DIR/pi-blackhole/pi-blackhole-config.json"
cmp "$tmp/mcp-registration" "$project/.mcp.json"
cmp "$tmp/mcp-registration" "$HOME/.claude.json"
assert_absent 'pi-blackhole' "$MOCK_PI_LOG"

# Web access: dry-run writes nothing and does not run pi. Registered packages are not installed again.
# Both harnesses expose the right tools without granting them to Iris.
: > "$MOCK_PI_LOG"
: > "$MOCK_PI_CALLS"
"$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web --dry-run > "$tmp/web-dry"
grep -Fxq 'INSTALL IF ABSENT: pi install npm:@tintinweb/pi-subagents' "$tmp/web-dry"
grep -Fxq 'INSTALL IF ABSENT: pi install npm:pi-web-access' "$tmp/web-dry"
[[ ! -s "$MOCK_PI_LOG" && ! -s "$MOCK_PI_CALLS" ]]
"$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web > "$tmp/web-initial"
assert_absent '^pi install \|^WRITE ' "$tmp/web-initial"
assert_absent '^pi install ' "$MOCK_PI_LOG"
for role in nora felix vera; do
  grep -q 'ext:pi-web-access/web_search' "$project/.pi/agents/$role.md"
  grep -q 'ext:pi-web-access/fetch_content' "$project/.pi/agents/$role.md"
  grep -q 'ext:pi-web-access/web_enable' "$project/.pi/agents/$role.md"
  grep -q 'WebSearch, WebFetch' "$project/.claude/agents/$role.md"
done
assert_absent 'pi-web-access/' "$project/.pi/agents/iris.md"
assert_absent 'WebSearch' "$project/.claude/agents/iris.md"
grep -q '## Web research' "$project/AGENTS.md"
: > "$MOCK_PI_LOG"
MOCK_PI_PACKAGES='npm:@tintinweb/pi-subagents' HOME="$pkg_home" PI_CODING_AGENT_DIR="$pkg_home/.pi/agent" \
  "$root/install.sh" --harness pi --scope project --target "$pkg_project" --no-web > "$tmp/web-one"
grep -Fxq 'pi install npm:pi-web-access' "$MOCK_PI_LOG"
assert_absent 'pi install npm:@tintinweb/pi-subagents\|install -l' "$MOCK_PI_LOG"
[[ "$(grep -c '^pi install ' "$MOCK_PI_LOG")" -eq 1 ]]
MOCK_PI_PACKAGES="$both_pi_packages" \
  "$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web > "$tmp/web-again"
grep -Fq 'SKIP PI PACKAGE: npm:pi-web-access is already registered; unchanged.' "$tmp/web-again"
assert_absent '^WRITE \|^pi install ' "$tmp/web-again"
[[ "$(grep -c '^pi install ' "$MOCK_PI_LOG")" -eq 1 ]]

# Antigravity CLI project-scope install, parallel workstream contracts, and idempotence.
"$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/agy-project"
[[ -f "$project/.agents/rules/AGENTS.md" && ! -e "$project/.agents/plugin.json" ]]
[[ -f "$project/.agents/skills/verification/SKILL.md" ]]
[[ -x "$project/.agents/skills/verification/scripts/check-ownership.sh" ]]
[[ -x "$project/.agents/skills/verification/scripts/check-readonly.sh" ]]
[[ ! -e "$project/.agents/skills/ui-ux" ]]
cmp -s "$root/skills/alien-science-ideation/SKILL.md" "$project/.agents/skills/alien-science-ideation/SKILL.md"
cmp -s "$root/skills/alien-science-ideation/references/discovery-workflow.md" "$project/.agents/skills/alien-science-ideation/references/discovery-workflow.md"
grep -q 'opt-in' "$project/.agents/skills/alien-science-ideation/SKILL.md"
assert_absent 'Always-on' "$project/.agents/skills/alien-science-ideation/SKILL.md"
cmp -s "$root/skills/weight-space-network-audit/SKILL.md" "$project/.agents/skills/weight-space-network-audit/SKILL.md"
assert_refs "$project/.agents/skills/weight-space-network-audit/references"
grep -q '^## Opt-in Alien Science Ideation$' "$project/.agents/rules/AGENTS.md"
assert_absent 'Alien Science Ideation is always on' "$project/.agents/rules/AGENTS.md"
assert_absent 'Always-on Alien Science' "$project/.agents/rules/AGENTS.md"
[[ ! -e "$project/.agents/agents/albert.md" ]]
for role in nora felix vera iris; do
  [[ -f "$project/.agents/agents/$role.md" ]]
  grep -q "^name: $role$" "$project/.agents/agents/$role.md"
  grep -q '^subagent: true$' "$project/.agents/agents/$role.md"
  grep -q '^mainAgent: false$' "$project/.agents/agents/$role.md"
  grep -q 'Open with a headline' "$project/.agents/agents/$role.md"
  assert_absent 'Alien Science Ideation is always on' "$project/.agents/agents/$role.md"
  assert_absent 'Always-on Alien Science' "$project/.agents/agents/$role.md"
done
for rule in 'Dynamic workstreams, ownership, and acceptance' 'Exclusive write ownership' 'Independent verification gate' 'Peer messages are coordination, not authority'; do
  grep -q "$rule" "$project/.agents/rules/AGENTS.md"
done
grep -q 'exclusive owned files/path patterns' "$project/.agents/agents/felix.md"
grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$project/.agents/agents/vera.md"
grep -q 'integration acceptance separately' "$project/.agents/agents/iris.md"
grep -q 'coordinator authority' "$project/.agents/agents/nora.md"
[[ "$(grep -c '<!-- QUINTET MANAGED START -->' "$project/.agents/rules/AGENTS.md")" -eq 1 ]]
"$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/agy-project-again"
assert_absent '^WRITE ' "$tmp/agy-project-again"

# Antigravity CLI global-scope install under mocked HOME without touching real $HOME.
# The preview must name the quintet plugin directory before anything is written.
agy_dry_home="$tmp/agy-dry-home"
mkdir -p "$agy_dry_home"
HOME="$agy_dry_home" XDG_CONFIG_HOME="$agy_dry_home/.config" "$root/install.sh" --harness antigravity --scope global --dry-run > "$tmp/agy-global-preview"
grep -q "^WRITE $agy_dry_home/.gemini/config/plugins/quintet/plugin.json$" "$tmp/agy-global-preview"
grep -q "^WRITE $agy_dry_home/.gemini/config/plugins/quintet/agents/nora.md$" "$tmp/agy-global-preview"
assert_absent 'agents/albert.md' "$tmp/agy-global-preview"
assert_absent 'plugins/albert' "$tmp/agy-global-preview"
[[ ! -e "$agy_dry_home/.gemini" ]]
mock_home="$HOME"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-global"
agy_global="$mock_home/.gemini/config/plugins/quintet"
[[ "$(basename -- "$agy_global")" == quintet ]]
[[ -f "$agy_global/plugin.json" && -f "$agy_global/rules/AGENTS.md" ]]
[[ ! -e "$mock_home/.gemini/config/plugins/albert" ]]
[[ -x "$agy_global/skills/verification/scripts/check-ownership.sh" ]]
[[ -x "$agy_global/skills/verification/scripts/check-readonly.sh" ]]
cmp -s "$root/skills/alien-science-ideation/SKILL.md" "$agy_global/skills/alien-science-ideation/SKILL.md"
cmp -s "$root/skills/alien-science-ideation/references/discovery-workflow.md" "$agy_global/skills/alien-science-ideation/references/discovery-workflow.md"
grep -q 'opt-in' "$agy_global/skills/alien-science-ideation/SKILL.md"
assert_absent 'Always-on' "$agy_global/skills/alien-science-ideation/SKILL.md"
cmp -s "$root/skills/weight-space-network-audit/SKILL.md" "$agy_global/skills/weight-space-network-audit/SKILL.md"
assert_refs "$agy_global/skills/weight-space-network-audit/references"
grep -q '^## Opt-in Alien Science Ideation$' "$agy_global/rules/AGENTS.md"
assert_absent 'Alien Science Ideation is always on' "$agy_global/rules/AGENTS.md"
assert_absent 'Always-on Alien Science' "$agy_global/rules/AGENTS.md"
grep -q '"name": "quintet"' "$agy_global/plugin.json"
[[ ! -e "$mock_home/.config/quintet/PERSONALITY.md" ]]
grep -q '"displayName": "Denia"' "$agy_global/plugin.json"
# Global Antigravity rules carry the full coordinator contract; no redundant agents/albert.md is written.
grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$agy_global/rules/AGENTS.md"
grep -q '^## Dispatch$' "$agy_global/rules/AGENTS.md"
grep -q '^## Delegation gate$' "$agy_global/rules/AGENTS.md"
grep -q '^## Main-agent personality' "$agy_global/rules/AGENTS.md"
assert_absent 'cross-project policy' "$agy_global/rules/AGENTS.md"
[[ ! -e "$agy_global/agents/albert.md" ]]
for role in nora felix vera iris; do
  [[ -f "$agy_global/agents/$role.md" ]]
  assert_absent 'Alien Science Ideation is always on' "$agy_global/agents/$role.md"
  assert_absent 'Always-on Alien Science' "$agy_global/agents/$role.md"
done
for role in nora felix vera iris; do grep -q "^name: $role$" "$agy_global/agents/$role.md"; done
grep -q 'exclusive owned files/path patterns' "$agy_global/agents/felix.md"
grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$agy_global/agents/vera.md"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-global-again"
assert_absent '^WRITE ' "$tmp/agy-global-again"
assert_absent '^ARCHIVE ' "$tmp/agy-global-again"
assert_absent '^KEEP ' "$tmp/agy-global-again"

# Switch every harness within each scope. Preview leaves existing rules alone,
# switches write only the instructions, and reinstalling either version is a no-op.
project_rules=("$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md")
global_rules=("$PI_CODING_AGENT_DIR/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$agy_global/rules/AGENTS.md")
printf 'Customized project coordinator\n' > "$project/.agents/agents/albert.md"
export MOCK_PI_PACKAGES=$'npm:@tintinweb/pi-subagents\nnpm:pi-web-access'
for scope in project global; do
  if [[ "$scope" == project ]]; then
    scope_args=(--scope project --target "$project")
    rules=("${project_rules[@]}")
    rule_backups="$project/.quintet-rule-backups"
  else
    scope_args=(--scope global)
    rules=("${global_rules[@]}")
    rule_backups="$HOME/.gemini/config/quintet-rule-backups"
  fi
  agy_rule="${rules[2]}"
  for file in "${rules[@]}"; do assert_workflow v2 "$file"; done
  "$root/install.sh" --harness pi,claude,antigravity "${scope_args[@]}" --workflow v1 --dry-run > "$tmp/workflow-preview"
  grep -Fxq 'WORKFLOW v1' "$tmp/workflow-preview"
  for file in "${rules[@]}"; do assert_workflow v2 "$file"; done
  grep -Fq "BACKUP RULE '$agy_rule' under '$rule_backups' (dry run)" "$tmp/workflow-preview"
  [[ ! -e "$rule_backups" ]]

  backup_count=0
  for edition in v1 v2; do
    cp -- "$agy_rule" "$tmp/previous-rule-$edition"
    "$root/install.sh" --harness pi,claude,antigravity "${scope_args[@]}" --workflow "$edition" > "$tmp/workflow-switch"
    grep -Fxq "WORKFLOW $edition" "$tmp/workflow-switch"
    [[ "$(grep -c '^WRITE ' "$tmp/workflow-switch")" -eq 3 ]]
    for file in "${rules[@]}"; do
      grep -Fxq "WRITE $file" "$tmp/workflow-switch"
      assert_workflow "$edition" "$file"
    done
    [[ "$(wc -c < "$agy_rule")" -le 24000 ]]
    [[ "$(ls -A -- "${agy_rule%/*}")" == AGENTS.md ]]
    saved_rule="$(find "$rule_backups" -type f -name AGENTS.md -exec cmp -s -- {} "$tmp/previous-rule-$edition" \; -print)"
    [[ -f "$saved_rule" ]]
    grep -Fxq "BACKUP RULE '$agy_rule' -> '$saved_rule'" "$tmp/workflow-switch"
    backup_count=$((backup_count + 1))
    [[ "$(find "$rule_backups" -type f | wc -l)" -eq "$backup_count" ]]
    if [[ "$scope" == project ]]; then
      for file in "${global_rules[@]}"; do assert_workflow v2 "$file"; done
    fi
    "$root/install.sh" --harness pi,claude,antigravity "${scope_args[@]}" --workflow "$edition" > "$tmp/workflow-again"
    assert_absent '^WRITE \|^BACKUP RULE \|^RELOCATE RULE ' "$tmp/workflow-again"
  done

  # The exact old generated name also covers user-only first-install backups.
  stale="$agy_rule.albert-backup-20261127101515-202082"
  user_only="$agy_rule.albert-backup-20261127101515-202083"
  link="$agy_rule.albert-backup-20261127101515-202084"
  special="$agy_rule.albert-backup-20261127101515-202085"
  other="$agy_rule.albert-backup-20261127101515-notes"
  cp -- "$tmp/previous-rule-v2" "$tmp/stale-rule"
  printf '\nCustom text from the previous install.\n' >> "$tmp/stale-rule"
  printf '# User rule with no final newline' > "$tmp/user-only-rule"
  cp -- "$tmp/stale-rule" "$stale"
  cp -- "$tmp/stale-rule" "$other"
  cp -- "$tmp/user-only-rule" "$user_only"
  ln -s -- "$tmp/stale-rule" "$link"
  if "$root/install.sh" --harness antigravity "${scope_args[@]}" --dry-run > "$tmp/unsafe-preview"; then exit 1; fi
  grep -Fq "KEEP RULE '$link':" "$tmp/unsafe-preview"
  grep -Fq 'outside rule discovery' "$tmp/unsafe-preview"
  assert_absent '^WRITE \|^RELOCATE RULE ' "$tmp/unsafe-preview"
  [[ "$(readlink -- "$link")" == "$tmp/stale-rule" ]]
  mv -- "$link" "$tmp/manual-link-$scope"
  mkfifo -- "$special"
  if "$root/install.sh" --harness antigravity "${scope_args[@]}" > "$tmp/unsafe-relocate"; then exit 1; fi
  grep -Fq "KEEP RULE '$special':" "$tmp/unsafe-relocate"
  assert_absent '^WRITE \|^RELOCATE RULE ' "$tmp/unsafe-relocate"
  [[ -p "$special" ]]
  mv -- "$special" "$tmp/manual-fifo-$scope"
  "$root/install.sh" --harness antigravity "${scope_args[@]}" --dry-run > "$tmp/relocate-preview"
  grep -Fxq "RELOCATE RULE '$stale' under '$rule_backups' (dry run)" "$tmp/relocate-preview"
  grep -Fxq "RELOCATE RULE '$user_only' under '$rule_backups' (dry run)" "$tmp/relocate-preview"
  [[ "$(grep -c '^RELOCATE RULE ' "$tmp/relocate-preview")" -eq 2 ]]
  [[ "$(find "$rule_backups" -type f | wc -l)" -eq "$backup_count" ]]
  cmp -- "$tmp/stale-rule" "$stale"
  cmp -- "$tmp/user-only-rule" "$user_only"
  "$root/install.sh" --harness antigravity "${scope_args[@]}" > "$tmp/relocate"
  assert_absent '^WRITE \|^ARCHIVE \|^KEEP ' "$tmp/relocate"
  [[ ! -e "$stale" && ! -e "$user_only" && "$(grep -c '^RELOCATE RULE ' "$tmp/relocate")" -eq 2 ]]
  relocated="$(find "$rule_backups" -type f -name "${stale##*/}")"
  cmp -- "$tmp/stale-rule" "$relocated"
  cmp -- "$tmp/user-only-rule" "$(find "$rule_backups" -type f -name "${user_only##*/}")"
  grep -Fxq "RELOCATE RULE '$stale' -> '$relocated'" "$tmp/relocate"
  cmp -- "$tmp/stale-rule" "$other"
  "$root/install.sh" --harness antigravity "${scope_args[@]}" > "$tmp/relocate-again"
  assert_absent '^WRITE \|^BACKUP RULE \|^RELOCATE RULE ' "$tmp/relocate-again"
done
unset MOCK_PI_PACKAGES
for file in "${project_rules[@]}" "${global_rules[@]}"; do
  grep -Fq 'Use the installed project workflow for the active' "$file"
  grep -Fq 'Otherwise use the installed global workflow.' "$file"
done
grep -Fxq 'Keep this rule.' "$project/AGENTS.md"
grep -Fxq 'Keep this too.' "$project/CLAUDE.md"
grep -Fxq 'Customized project coordinator' "$project/.agents/agents/albert.md"

# Legacy plugins/albert migration. Fixtures come from the archived installer at abab658, the
# last revision that wrote plugins/albert, so the legacy layout is a real older tree instead of
# a copy of today's layout.
legacy_src="$tmp/legacy-src"
mkdir -p "$legacy_src"
git -C "$root" archive abab658 | tar -x -C "$legacy_src"
seed_home="$tmp/seed-home"
mkdir -p "$seed_home"
HOME="$seed_home" XDG_CONFIG_HOME="$seed_home/.config" bash "$legacy_src/install.sh" --harness antigravity --scope global > "$tmp/agy-seed"
seed_plugin="$seed_home/.gemini/config/plugins/albert"
[[ -f "$seed_plugin/plugin.json" && -f "$seed_plugin/rules/AGENTS.md" && -f "$seed_plugin/agents/nora.md" ]]
seed_legacy() { mkdir -p "$1/.gemini/config/plugins"; cp -a "$seed_plugin" "$1/.gemini/config/plugins/albert"; }

# An eligible legacy tree is archived intact, including edits inside generated files.
old_home="$tmp/old-home"
old_dir="$old_home/.gemini/config/plugins/albert"
seed_legacy "$old_home"
printf '\nCustomized legacy worker instruction.\n' >> "$old_dir/agents/felix.md"
printf '\nCustomized legacy skill.\n' >> "$old_dir/skills/verification/SKILL.md"
printf 'Original user instructions.\n' > "$old_dir/rules/AGENTS.md.albert-backup-20261127101515-202082"
cp -a "$old_dir" "$tmp/expected-archive"
HOME="$old_home" XDG_CONFIG_HOME="$old_home/.config" "$root/install.sh" --harness antigravity --scope global \
  --workflow v1 > "$tmp/agy-old"
[[ ! -e "$old_dir" ]]
archives=("$old_home"/.gemini/config/quintet-backups/albert.*/albert)
[[ "${#archives[@]}" -eq 1 ]]
grep -Fxq "ARCHIVE '$old_dir' -> '${archives[0]}'" "$tmp/agy-old"
diff -r -- "$tmp/expected-archive" "${archives[0]}"
[[ -f "$old_home/.gemini/config/plugins/quintet/plugin.json" && -f "$old_home/.gemini/config/plugins/quintet/agents/felix.md" ]]
assert_workflow v1 "$old_home/.gemini/config/plugins/quintet/rules/AGENTS.md"
assert_absent '^CARRY ' "$tmp/agy-old"
# A rerun after migration performs no writes and leaves a single active plugin.
HOME="$old_home" XDG_CONFIG_HOME="$old_home/.config" "$root/install.sh" --harness antigravity --scope global \
  --workflow v1 > "$tmp/agy-old-again"
assert_absent '^ARCHIVE ' "$tmp/agy-old-again"
assert_absent '^KEEP ' "$tmp/agy-old-again"
assert_absent '^WRITE ' "$tmp/agy-old-again"
[[ "$(ls -A "$old_home/.gemini/config/plugins")" == quintet ]]

# Switching a live Quintet install while carrying legacy rules writes twice. Both previous
# versions survive. A matching fenced example is not an active copy of the carried rules.
carry_home="$tmp/carry-home"
carry_dir="$carry_home/.gemini/config/plugins/albert"
carry_rules="$carry_dir/rules/AGENTS.md"
carry_quintet="$carry_home/.gemini/config/plugins/quintet"
carry_dest="$carry_quintet/rules/AGENTS.md"
mkdir -p "$carry_home"
HOME="$carry_home" "$root/install.sh" --harness antigravity --scope global --workflow v2 > "$tmp/agy-carry-seed"
seed_legacy "$carry_home"
printf '\n## House rules\nKeep our bespoke policy.\n' >> "$carry_rules"
{
  printf 'Example of the old rules:\n\n```markdown\n<!-- QUINTET LEGACY CARRY START -->\n'
  awk '$0=="<!-- ALBERT MANAGED START -->" {inside=1; next}
    $0=="<!-- ALBERT MANAGED END -->" {inside=0; next} !inside {print}' "$carry_rules"
  printf '<!-- QUINTET LEGACY CARRY END -->\n```\n\n'
  cat -- "$carry_dest"
} > "$tmp/carry-v2"
cp -- "$tmp/carry-v2" "$carry_dest"
HOME="$carry_home" "$root/install.sh" --harness antigravity --scope global --workflow v1 > "$tmp/agy-carry"
grep -Fxq "CARRY '$carry_rules' -> '$carry_dest' (your text outside the managed block was preserved)" "$tmp/agy-carry"
grep -Fq "ARCHIVE '$carry_dir' -> '$carry_home/.gemini/config/quintet-backups/" "$tmp/agy-carry"
[[ "$(ls -A -- "$carry_quintet/rules")" == AGENTS.md ]]
carry_backups=("$carry_home"/.gemini/config/quintet-rule-backups/rule.*/AGENTS.md)
[[ "${#carry_backups[@]}" -eq 2 ]]
[[ "$(grep -c '^BACKUP RULE ' "$tmp/agy-carry")" -eq 2 ]]
saved_v2="$(grep -lFx -- '## Workflow v2' "${carry_backups[@]}")"
saved_v1="$(grep -lFx -- '## Workflow v1' "${carry_backups[@]}")"
cmp -- "$tmp/carry-v2" "$saved_v2"
prefix_bytes "$tmp/carry-v2" > "$tmp/carry-v2-prefix"
prefix_bytes "$saved_v1" > "$tmp/carry-v1-prefix"
cmp -- "$tmp/carry-v2-prefix" "$tmp/carry-v1-prefix"
assert_workflow v1 "$carry_dest"
awk '
  /^```/ { fenced=!fenced; next }
  fenced { next }
  $0 == "<!-- QUINTET LEGACY CARRY START -->" { if (managed) exit 1; carry=1; next }
  $0 == "<!-- QUINTET LEGACY CARRY END -->" { carry=0; next }
  $0 == "<!-- QUINTET MANAGED START -->" { managed=1 }
  carry && $0 == "Keep our bespoke policy." { rules++ }
  END { if (rules != 1) exit 1 }
' "$carry_dest"
[[ "$(grep -Fxc 'Keep our bespoke policy.' "$carry_dest")" -eq 2 ]]
[[ ! -e "$carry_dir" ]]

# A failed rename keeps the source intact. Retry leaves an unchanged carry alone and
# replaces it in place if the source changes, backing up the prior rules.
retry_home="$tmp/retry-home"
retry_dir="$retry_home/.gemini/config/plugins/albert"
retry_backup_root="$retry_home/.gemini/config/quintet-backups"
retry_dest="$retry_home/.gemini/config/plugins/quintet/rules/AGENTS.md"
seed_legacy "$retry_home"
printf '\nKeep this on retry.\n' >> "$retry_dir/rules/AGENTS.md"
cp -a -- "$retry_dir" "$tmp/retry-original"
mkdir -p "$tmp/fail-rename"
cat > "$tmp/fail-rename/mv" <<'MV'
#!/usr/bin/env bash
case "$1" in
  --help) printf '  --no-copy  do not copy across filesystems\n' ;;
  --no-copy) printf 'simulated cross-filesystem rename refusal\n' >&2; exit 1 ;;
  *) exec "$REAL_MV" "$@" ;;
esac
MV
chmod +x "$tmp/fail-rename/mv"
REAL_MV="$(command -v mv)" PATH="$tmp/fail-rename:$PATH" HOME="$retry_home" \
  "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-retry" 2>&1
grep -Fxq 'simulated cross-filesystem rename refusal' "$tmp/agy-retry"
grep -Fq "KEEP '$retry_dir': could not move the legacy plugin" "$tmp/agy-retry"
diff -r -- "$tmp/retry-original" "$retry_dir"
grep -Fxq 'Keep this on retry.' "$retry_dest"
awk '$0 == "<!-- QUINTET MANAGED START -->" { print "User rule after the carry.\n" } { print }' \
  "$retry_dest" > "$tmp/retry-dest-before"
cp -- "$tmp/retry-dest-before" "$retry_dest"
REAL_MV="$(command -v mv)" PATH="$tmp/fail-rename:$PATH" HOME="$retry_home" \
  "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-retry-same" 2>&1
assert_absent '^WRITE \|^BACKUP RULE ' "$tmp/agy-retry-same"
cmp -- "$tmp/retry-dest-before" "$retry_dest"
cp -- "$seed_plugin/rules/AGENTS.md" "$retry_dir/rules/AGENTS.md"
printf '\nUse my updated rule instead.\n' >> "$retry_dir/rules/AGENTS.md"
cp -- "$retry_dir/rules/AGENTS.md" "$tmp/retry-source-edited"
HOME="$retry_home" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-retry-again"
grep -Fq "ARCHIVE '$retry_dir' -> '$retry_backup_root/" "$tmp/agy-retry-again"
[[ ! -e "$retry_dir" ]]
retry_archive=("$retry_backup_root"/albert.*/albert/rules/AGENTS.md)
[[ "${#retry_archive[@]}" -eq 1 ]]
cmp -- "$tmp/retry-source-edited" "${retry_archive[0]}"
assert_absent 'Keep this on retry\.' "$retry_dest"
[[ "$(grep -Fxc '<!-- QUINTET LEGACY CARRY START -->' "$retry_dest")" -eq 1 ]]
awk '
  $0 == "Use my updated rule instead." { rule=NR }
  $0 == "User rule after the carry." { after=NR }
  END { if (!rule || rule >= after) exit 1 }
' "$retry_dest"
retry_backups=("$retry_home"/.gemini/config/quintet-rule-backups/rule.*/AGENTS.md)
cmp -- "$tmp/retry-dest-before" "$(grep -lFx 'Keep this on retry.' "${retry_backups[@]}")"

# A dry run previews the carry and archive and changes nothing.
dry_home="$tmp/dry-home"
dry_dir="$dry_home/.gemini/config/plugins/albert"
seed_legacy "$dry_home"
printf '\n## House rules\nDry run text.\n' >> "$dry_dir/rules/AGENTS.md"
HOME="$dry_home" XDG_CONFIG_HOME="$dry_home/.config" "$root/install.sh" --harness antigravity --scope global --dry-run > "$tmp/agy-dry-legacy"
grep -q "^CARRY '$dry_dir/rules/AGENTS.md' -> '$dry_home/.gemini/config/plugins/quintet/rules/AGENTS.md' (dry run; your text outside the managed block would be preserved)$" "$tmp/agy-dry-legacy"
grep -Fxq "ARCHIVE '$dry_dir' under '$dry_home/.gemini/config/quintet-backups' (dry run; preserve the intact legacy plugin)" "$tmp/agy-dry-legacy"
grep -Fq "BACKUP RULE '$dry_home/.gemini/config/plugins/quintet/rules/AGENTS.md' under '$dry_home/.gemini/config/quintet-rule-backups' (dry run;" "$tmp/agy-dry-legacy"
[[ -f "$dry_dir/rules/AGENTS.md" ]]
[[ ! -e "$dry_home/.gemini/config/plugins/quintet" && ! -e "$dry_home/.gemini/config/quintet-backups" ]]
[[ ! -e "$dry_home/.gemini/config/quintet-rule-backups" ]]

# Entries this installer does not write stop the migration and are named.
keep_home="$tmp/keep-home"
keep_dir="$keep_home/.gemini/config/plugins/albert"
keep_quintet="$keep_home/.gemini/config/plugins/quintet"
seed_legacy "$keep_home"
mkdir -p "$keep_dir/skills/my-own-skill" "$keep_dir/skills/empty-dir"
printf 'my own skill\n' > "$keep_dir/skills/my-own-skill/SKILL.md"
printf 'my own notes\n' > "$keep_dir/notes.txt"
keep_sum="$(cd "$keep_dir" && find . -type f -exec cksum {} + | sort)"
keep_backup="$keep_dir/rules/AGENTS.md.albert-backup-20261127101515-202082"
cp -- "$tmp/user-only-rule" "$keep_backup"
HOME="$keep_home" XDG_CONFIG_HOME="$keep_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-keep"
grep -q "^KEEP '$keep_dir': legacy Antigravity plugin kept because it holds entries this installer does not write.$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/notes.txt'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/my-own-skill'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/my-own-skill/SKILL.md'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/empty-dir'$" "$tmp/agy-keep"
grep -Fxq "  Inspect those entries before moving '$keep_dir' outside plugin discovery." "$tmp/agy-keep"
assert_absent '^ARCHIVE ' "$tmp/agy-keep"
assert_absent '^CARRY ' "$tmp/agy-keep"
[[ ! -e "$keep_backup" ]]
grep -Fq "RELOCATE RULE '$keep_backup' -> " "$tmp/agy-keep"
cmp -- "$tmp/user-only-rule" "$(find "$keep_home/.gemini/config/quintet-rule-backups" -type f -name "${keep_backup##*/}")"
[[ "$(cd "$keep_dir" && find . -type f -exec cksum {} + | sort)" == "$keep_sum" ]]
[[ -d "$keep_dir/skills/empty-dir" && -f "$keep_quintet/plugin.json" ]]

# Any symlink inside the legacy tree stops migration, is named as EXTRA, and survives intact.
link_home="$tmp/link-home"
link_dir="$link_home/.gemini/config/plugins/albert"
link_target="$tmp/link-target"
seed_legacy "$link_home"
mkdir -p "$link_target"
printf 'outside data\n' > "$link_target/keep.txt"
ln -s "$link_target" "$link_dir/skills/linked"
HOME="$link_home" XDG_CONFIG_HOME="$link_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-link"
grep -q "^KEEP '$link_dir': legacy Antigravity plugin kept because it holds entries this installer does not write.$" "$tmp/agy-link"
grep -q "^  EXTRA '$link_dir/skills/linked'$" "$tmp/agy-link"
assert_absent '^ARCHIVE ' "$tmp/agy-link"
[[ -L "$link_dir/skills/linked" ]]
[[ -f "$link_target/keep.txt" && "$(cat "$link_target/keep.txt")" == 'outside data' ]]

# Unmergeable markers keep the tree and name the file instead of dropping text.
broken_home="$tmp/broken-home"
broken_dir="$broken_home/.gemini/config/plugins/albert"
seed_legacy "$broken_home"
# Even after a valid pair, a second unmatched START must not hide user rules.
printf '\n<!-- ALBERT MANAGED START -->\nDo not drop this rule.\n' >> "$broken_dir/rules/AGENTS.md"
cp -a -- "$broken_dir" "$tmp/broken-original"
HOME="$broken_home" XDG_CONFIG_HOME="$broken_home/.config" "$root/install.sh" --harness antigravity --scope global 2>/dev/null > "$tmp/agy-broken"
grep -Fxq "KEEP '$broken_dir': '$broken_dir/rules/AGENTS.md' has managed markers that cannot be merged safely." "$tmp/agy-broken"
assert_absent '^ARCHIVE \|^CARRY ' "$tmp/agy-broken"
diff -r -- "$tmp/broken-original" "$broken_dir"

# An incomplete walk never archives the plugin.
guard_home="$tmp/guard-home"
guard_dir="$guard_home/.gemini/config/plugins/albert"
seed_legacy "$guard_home"
mkdir -p "$guard_dir/skills/locked"
printf 'x\n' > "$guard_dir/skills/locked/file"
chmod 000 "$guard_dir/skills/locked"
HOME="$guard_home" XDG_CONFIG_HOME="$guard_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-guard" 2>/dev/null
grep -Fxq "KEEP '$guard_dir': the legacy plugin directory could not be enumerated." "$tmp/agy-guard"
[[ -f "$guard_dir/plugin.json" ]]
chmod 700 "$guard_dir/skills/locked"

# A third-party plugin in plugins/albert is neither claimed nor reported.
foreign_home="$tmp/foreign-home"
foreign_dir="$foreign_home/.gemini/config/plugins/albert"
mkdir -p "$foreign_dir/agents" "$foreign_dir/rules"
printf '{\n  "name": "albert",\n  "displayName": "Albert"\n}\n' > "$foreign_dir/plugin.json"
printf -- '---\nname: albert\nmainAgent: true\n---\n\nA third-party Albert plugin.\n' > "$foreign_dir/agents/albert.md"
printf '# Third-party rules\n' > "$foreign_dir/rules/AGENTS.md"
HOME="$foreign_home" XDG_CONFIG_HOME="$foreign_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-foreign"
assert_absent '^ARCHIVE ' "$tmp/agy-foreign"
assert_absent '^KEEP ' "$tmp/agy-foreign"
assert_absent 'rm -rf' "$tmp/agy-foreign"
[[ -f "$foreign_dir/agents/albert.md" && -f "$foreign_dir/rules/AGENTS.md" ]]
# Quintet's four worker filenames alone, without generated Quintet text, are not enough.
partial_home="$tmp/partial-home"
partial_dir="$partial_home/.gemini/config/plugins/albert"
mkdir -p "$partial_dir/agents"
for role in nora felix vera iris; do printf 'alpha worker\n' > "$partial_dir/agents/$role.md"; done
printf 'alpha coordinator\n' > "$partial_dir/agents/albert.md"
HOME="$partial_home" XDG_CONFIG_HOME="$partial_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-partial"
assert_absent '^ARCHIVE ' "$tmp/agy-partial"
assert_absent '^KEEP ' "$tmp/agy-partial"
[[ -f "$partial_dir/agents/albert.md" ]]

# Project personality sits beside AGENTS.md and changes only the main agent.
cat > "$project/PERSONALITY.md" <<'PERSONA'
Name: Kanade

# Personality
Use short, factual summaries.
PERSONA
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" --workflow v1 > "$tmp/personalized"
for file in "$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md"; do
  grep -q 'Name: Kanade' "$file"
  grep -q 'Use short, factual summaries.' "$file"
done
for role in nora felix vera iris; do
  assert_absent 'Name: Kanade' "$project/.pi/agents/$role.md"
  assert_absent 'Name: Kanade' "$project/.claude/agents/$role.md"
  assert_absent 'Name: Kanade' "$project/.agents/agents/$role.md"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" --workflow v1 > "$tmp/personalized-again"
assert_absent '^WRITE ' "$tmp/personalized-again"
grep -q '^Name: Kanade' "$project/PERSONALITY.md"

# Invalid project personality must fail before writes.
printf 'Not a valid header\n' > "$project/PERSONALITY.md"
if "$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/invalid" 2>&1; then
  echo 'Invalid personality was accepted' >&2
  exit 1
fi
grep -q 'Personality must start' "$tmp/invalid"
assert_absent '^WRITE ' "$tmp/invalid"

# Global identity comes from the repository root; the installer never edits it.
custom_source="$tmp/custom-source"
mkdir -p "$custom_source"
cp -a "$root/." "$custom_source/"
"$custom_source/install.sh" --harness pi --scope project --target "$custom_source" --workflow v1 --no-web > "$tmp/install-in-source"
"$custom_source/install.sh" --harness pi --scope project --target "$custom_source" --workflow v1 --no-web > "$tmp/install-in-source-again"
assert_absent '^WRITE ' "$tmp/install-in-source-again"
grep -Fqx '## Workflow v1' "$custom_source/AGENTS.md"
grep -Fq 'QUINTET WORKFLOW' "$custom_source/AGENTS.md"
"$custom_source/install.sh" --harness pi --scope project --target "$custom_source" --workflow v2 --no-web > "$tmp/switch-in-source"
grep -Fqx '## Workflow v2' "$custom_source/AGENTS.md"
assert_absent '^## Workflow v1$' "$custom_source/AGENTS.md"
printf 'Name: Rei\n\n# Personality\nKeep it short.\n' > "$custom_source/PERSONALITY.md"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$custom_source/install.sh" --harness antigravity --scope global > "$tmp/renamed-global"
grep -q '"displayName": "Rei"' "$agy_global/plugin.json"
grep -q 'Name: Rei' "$agy_global/rules/AGENTS.md"
assert_workflow v2 "$agy_global/rules/AGENTS.md"
grep -q '^Name: Rei' "$custom_source/PERSONALITY.md"
[[ ! -e "$mock_home/.config/quintet/PERSONALITY.md" ]]
for role in nora felix vera iris; do assert_absent 'Name: Rei' "$agy_global/agents/$role.md"; done
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$custom_source/install.sh" --harness antigravity --scope global > "$tmp/renamed-again"
assert_absent '^WRITE ' "$tmp/renamed-again"

# No final newline must not join the managed end marker or cause reinstall writes.
printf 'Name: Kanade\n\n# Personality\nNo final newline' > "$project/PERSONALITY.md"
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/no-newline"
for file in "$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md"; do
  grep -Fqx 'No final newline' "$file"
  [[ "$(grep -Fxc '<!-- QUINTET MANAGED END -->' "$file")" -eq 1 ]]
  assert_absent 'No final newline<!-- QUINTET MANAGED END -->' "$file"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" --dry-run > "$tmp/no-newline-preview"
assert_absent '^WRITE ' "$tmp/no-newline-preview"
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/no-newline-again"
assert_absent '^WRITE ' "$tmp/no-newline-again"

# Reject both reserved marker lines, including CRLF, before writing anything.
for marker in 'QUINTET MANAGED START' 'QUINTET MANAGED END' 'ALBERT MANAGED START' 'ALBERT MANAGED END'; do
  printf 'Name: Kanade\r\n\r\n<!-- %s -->\r\nMore style.\r\n' "$marker" > "$project/PERSONALITY.md"
  if "$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/reserved" 2>&1; then
    echo "Accepted reserved marker: $marker" >&2
    exit 1
  fi
  grep -q 'Reserved managed marker' "$tmp/reserved"
  assert_absent '^WRITE ' "$tmp/reserved"
done

# CRLF headers and style lines should be accepted and rendered as LF.
printf 'Name: Rei\r\n\r\n# Personality\r\nKeep CRLF.\r\n' > "$project/PERSONALITY.md"
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/crlf"
for file in "$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md"; do
  grep -qx 'Name: Rei' "$file"
  grep -qx 'Keep CRLF.' "$file"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/crlf-again"
assert_absent '^WRITE ' "$tmp/crlf-again"

# A skill path blocked by a regular file must fail closed. Files this run created
# disappear, overwritten files come back, and the blocker is left untouched.
blocked="$tmp/blocked-skill"
mkdir -p "$blocked/.claude/agents" "$blocked/.claude/skills"
printf 'user nora\n' > "$blocked/.claude/agents/nora.md"
printf 'not a skill directory\n' > "$blocked/.claude/skills/verification"
printf '# Claude contract\nKeep this blocker text.\n' > "$blocked/CLAUDE.md"
printf 'leave me\n' > "$blocked/NOTES.txt"
snapshot_tree "$blocked" "$tmp/blocked-before"
"$root/install.sh" --harness claude --scope project --target "$blocked" --workflow v2 --no-tui --dry-run --no-web \
  > "$tmp/blocked-dry"
snapshot_tree "$blocked" "$tmp/blocked-dry-tree"
diff -u "$tmp/blocked-before" "$tmp/blocked-dry-tree"
rc=0
"$root/install.sh" --harness claude --scope project --target "$blocked" --workflow v2 --no-tui --no-web \
  > "$tmp/blocked-out" 2> "$tmp/blocked-err" || rc=$?
[[ "$rc" -ne 0 ]]
grep -Fq 'Not a directory' "$tmp/blocked-err"
grep -Fq 'Install failed; undid writes from this run.' "$tmp/blocked-err"
assert_absent '^DONE$' "$tmp/blocked-out"
snapshot_tree "$blocked" "$tmp/blocked-after"
diff -u "$tmp/blocked-before" "$tmp/blocked-after"
[[ -z "$(find "$blocked" -name '*.quintet-backup-*' -print -quit)" ]]
cmp -- <(printf 'not a skill directory\n') "$blocked/.claude/skills/verification"
cmp -- <(printf 'user nora\n') "$blocked/.claude/agents/nora.md"
# Removing the blocker lets the same project install finish, back up the
# nonidentical contract, and keep the text outside the managed markers.
rm -- "$blocked/.claude/skills/verification"
"$root/install.sh" --harness claude --scope project --target "$blocked" --workflow v2 --no-tui --no-web > "$tmp/blocked-retry"
assert_workflow v2 "$blocked/CLAUDE.md"
grep -Fxq 'Keep this blocker text.' "$blocked/CLAUDE.md"
for role in nora felix vera iris; do
  [[ -f "$blocked/.claude/agents/$role.md" ]]
done
[[ -n "$(find "$blocked" -maxdepth 1 -name 'CLAUDE.md.quintet-backup-*' -print -quit)" ]]
[[ -f "$blocked/.claude/skills/verification/SKILL.md" ]]
v1_project="$tmp/workflow-v1-project"
mkdir -p "$v1_project"
"$root/install.sh" --harness claude --scope project --target "$v1_project" --workflow v1 --no-tui --no-web > "$tmp/workflow-v1-out"
assert_workflow v1 "$v1_project/CLAUDE.md"
for role in nora felix vera iris; do
  [[ -f "$v1_project/.claude/agents/$role.md" ]]
done
"$root/install.sh" --harness claude --scope project --target "$v1_project" --workflow v1 --no-tui --dry-run --no-web > "$tmp/workflow-v1-dry"
assert_absent '^WRITE ' "$tmp/workflow-v1-dry"

# The same blocked skill on a global Antigravity install must not archive or
# remove an eligible legacy tree, and must not leave the partial quintet plugin.
legacy_block_home="$tmp/legacy-block-home"
mkdir -p "$legacy_block_home"
seed_legacy "$legacy_block_home"
legacy_block_quintet="$legacy_block_home/.gemini/config/plugins/quintet"
mkdir -p "$legacy_block_quintet/rules" "$legacy_block_quintet/skills"
printf 'old rule\n' > "$legacy_block_quintet/rules/AGENTS.md"
printf 'block verification\n' > "$legacy_block_quintet/skills/verification"
snapshot_tree "$legacy_block_home/.gemini" "$tmp/legacy-block-before"
rc=0
HOME="$legacy_block_home" XDG_CONFIG_HOME="$legacy_block_home/.config" \
  "$root/install.sh" --harness antigravity --scope global --workflow v2 --no-tui --no-web \
  > "$tmp/legacy-block-out" 2> "$tmp/legacy-block-err" || rc=$?
[[ "$rc" -ne 0 ]]
grep -Fq 'Not a directory' "$tmp/legacy-block-err"
assert_absent '^ARCHIVE \|^DONE$' "$tmp/legacy-block-out"
snapshot_tree "$legacy_block_home/.gemini" "$tmp/legacy-block-after"
diff -u "$tmp/legacy-block-before" "$tmp/legacy-block-after"
[[ ! -e "$legacy_block_home/.gemini/config/quintet-backups" ]]
[[ ! -e "$legacy_block_home/.gemini/config/quintet-rule-backups" ]]
cmp -- <(printf 'old rule\n') "$legacy_block_quintet/rules/AGENTS.md"
cmp -- <(printf 'block verification\n') "$legacy_block_quintet/skills/verification"

# Pi packages are still installed before project writes. A blocked skill rolls
# the project tree back and does not publish subagents.json for the failed run.
pi_block="$tmp/pi-block"
pi_block_home="$tmp/pi-block-home"
mkdir -p "$pi_block/.pi/skills" "$pi_block_home"
printf 'block\n' > "$pi_block/.pi/skills/verification"
printf '# Pi contract\nKeep the pi rule.\n' > "$pi_block/AGENTS.md"
snapshot_tree "$pi_block" "$tmp/pi-block-before"
: > "$MOCK_PI_LOG"
rc=0
MOCK_PI_PACKAGES='npm:unrelated' HOME="$pi_block_home" PI_CODING_AGENT_DIR="$pi_block_home/.pi/agent" \
  "$root/install.sh" --harness pi --scope project --target "$pi_block" --workflow v2 --no-tui --no-web \
  > "$tmp/pi-block-out" 2> "$tmp/pi-block-err" || rc=$?
[[ "$rc" -ne 0 ]]
grep -Fxq 'pi install npm:@tintinweb/pi-subagents' "$MOCK_PI_LOG"
grep -Fxq 'pi install npm:pi-web-access' "$MOCK_PI_LOG"
[[ ! -e "$pi_block_home/.pi/agent/subagents.json" ]]
snapshot_tree "$pi_block" "$tmp/pi-block-after"
diff -u "$tmp/pi-block-before" "$tmp/pi-block-after"
[[ -z "$(find "$pi_block" -name '*.quintet-backup-*' -print -quit)" ]]
MOCK_PI_PACKAGES="$both_pi_packages"

# A failed package install must not be hidden by a later install that succeeds
# or by a package that is already listed. Parent writes nothing in that case.
for pi_fail_case in listed later; do
  pi_fail="$tmp/pi-fail-$pi_fail_case"
  pi_fail_home="$tmp/pi-fail-home-$pi_fail_case"
  mkdir -p "$pi_fail" "$pi_fail_home"
  printf 'leave me\n' > "$pi_fail/NOTES.txt"
  snapshot_tree "$pi_fail" "$tmp/pi-fail-$pi_fail_case-before"
  if [[ "$pi_fail_case" == listed ]]; then
    pi_fail_packages='npm:pi-web-access'
  else
    pi_fail_packages='npm:unrelated'
  fi
  : > "$MOCK_PI_LOG"
  rc=0
  MOCK_PI_INSTALL_FAIL='npm:@tintinweb/pi-subagents' MOCK_PI_PACKAGES="$pi_fail_packages" \
    HOME="$pi_fail_home" PI_CODING_AGENT_DIR="$pi_fail_home/.pi/agent" \
    "$root/install.sh" --harness pi --scope project --target "$pi_fail" --workflow v2 --no-tui --no-web \
    > "$tmp/pi-fail-$pi_fail_case-out" 2> "$tmp/pi-fail-$pi_fail_case-err" || rc=$?
  [[ "$rc" -ne 0 ]]
  assert_absent '^DONE$' "$tmp/pi-fail-$pi_fail_case-out"
  grep -Fxq 'pi install npm:@tintinweb/pi-subagents' "$MOCK_PI_LOG"
  assert_absent 'pi install npm:pi-web-access' "$MOCK_PI_LOG"
  [[ ! -e "$pi_fail_home/.pi/agent/subagents.json" ]]
  [[ ! -e "$pi_fail/PERSONALITY.md" && ! -e "$pi_fail/.pi" && ! -e "$pi_fail/AGENTS.md" ]]
  snapshot_tree "$pi_fail" "$tmp/pi-fail-$pi_fail_case-after"
  diff -u "$tmp/pi-fail-$pi_fail_case-before" "$tmp/pi-fail-$pi_fail_case-after"
done
unset MOCK_PI_INSTALL_FAIL
MOCK_PI_PACKAGES="$both_pi_packages"

# An unreadable agent body must not be installed as frontmatter and must not
# print DONE. Files this run created are removed.
unread_source="$tmp/unread-source"
unread_project="$tmp/unread-project"
mkdir -p "$unread_source" "$unread_project"
cp -a "$root/." "$unread_source/"
chmod a-r "$unread_source/agents/nora.md"
printf 'leave me\n' > "$unread_project/NOTES.txt"
snapshot_tree "$unread_project" "$tmp/unread-before"
rc=0
"$unread_source/install.sh" --harness claude --scope project --target "$unread_project" --workflow v2 --no-tui --no-web \
  > "$tmp/unread-out" 2> "$tmp/unread-err" || rc=$?
[[ "$rc" -ne 0 ]]
assert_absent '^DONE$' "$tmp/unread-out"
grep -Fq 'Install failed; undid writes from this run.' "$tmp/unread-err"
[[ ! -e "$unread_project/.claude/agents/nora.md" ]]
snapshot_tree "$unread_project" "$tmp/unread-after"
diff -u "$tmp/unread-before" "$tmp/unread-after"
cmp -- <(printf 'leave me\n') "$unread_project/NOTES.txt"

# A failing date while backing up a nonidentical contract must not exit 0,
# print DONE, leave an empty-stamp backup, or overwrite the user text.
date_project="$tmp/date-fail"
mkdir -p "$date_project" "$tmp/fail-date"
printf '# Claude contract\nKeep this user text.\n' > "$date_project/CLAUDE.md"
printf 'leave me\n' > "$date_project/NOTES.txt"
cat > "$tmp/fail-date/date" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$tmp/fail-date/date"
snapshot_tree "$date_project" "$tmp/date-before"
rc=0
PATH="$tmp/fail-date:$PATH" "$root/install.sh" --harness claude --scope project --target "$date_project" --workflow v2 --no-tui --no-web \
  > "$tmp/date-out" 2> "$tmp/date-err" || rc=$?
[[ "$rc" -ne 0 ]]
assert_absent '^DONE$' "$tmp/date-out"
grep -Fq 'Install failed; undid writes from this run.' "$tmp/date-err"
[[ -z "$(find "$date_project" -name '*.quintet-backup-*' -print -quit)" ]]
[[ -z "$(find "$date_project" -name 'CLAUDE.md.quintet-backup--*' -print -quit)" ]]
cmp -- <(printf '# Claude contract\nKeep this user text.\n') "$date_project/CLAUDE.md"
assert_absent 'QUINTET MANAGED' "$date_project/CLAUDE.md"
snapshot_tree "$date_project" "$tmp/date-after"
diff -u "$tmp/date-before" "$tmp/date-after"

echo 'install E2E PASS: harnesses, workflow switching, scope, idempotence, settings, web, personality and legacy archive'
