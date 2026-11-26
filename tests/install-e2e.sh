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
# Weight-audit references ship byte-for-byte. Enumerate the source tree so a new
# reference cannot be silently skipped; a missing installed copy fails the cmp.
assert_refs() {
  local dest="$1" ref
  for ref in "$root"/skills/weight-space-network-audit/references/*.md; do
    cmp -- "$ref" "$dest/${ref##*/}"
  done
}
# Byte-exact text before the managed block, so blank lines there are compared too.
prefix_bytes() {
  local file="$1" offset
  offset="$(grep -b -m1 -F -- '<!-- ALBERT MANAGED START -->' "$file" | cut -d: -f1)"
  head -c "$offset" -- "$file"
}
project="$tmp/kanade"
mkdir -p "$project" "$tmp/bin"
printf '# Kanade contract\nKeep this rule.\n' > "$project/AGENTS.md"
printf '# Claude contract\nKeep this too.\n' > "$project/CLAUDE.md"
cat > "$tmp/bin/pi" <<'PI'
#!/usr/bin/env bash
case "$1" in
  --version) printf 'pi %s\n' "${MOCK_PI_VERSION:-1.1.0}" ;;
  list) printf '%s\n' "${MOCK_PI_PACKAGES:-npm:@tintinweb/pi-subagents}" ;;
  install) printf 'pi %s\n' "$*" >> "$MOCK_PI_LOG" ;;
  *) exit 1 ;;
esac
PI
chmod +x "$tmp/bin/pi"
export PATH="$tmp/bin:$PATH" MOCK_PI_LOG="$tmp/pi-actions" MOCK_PI_VERSION=1.1.0
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" PI_CODING_AGENT_DIR="$tmp/home/.pi/agent"
mkdir -p "$HOME"

"$root/install.sh" --harness pi,claude --scope project --target "$project" --dry-run > "$tmp/dry"
[[ ! -d "$project/.pi" && ! -d "$project/.claude" && ! -e "$project/PERSONALITY.md" ]]
MOCK_PI_VERSION=0.87.1 "$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/version" 2>&1 && exit 1
! test -d "$project/.pi"
grep -q 'Pi >=1.1.0 required' "$tmp/version"
MOCK_PI_PACKAGES='npm:some-other-package' "$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/missing" 2>&1 && exit 1
! test -d "$project/.pi"
grep -q 'pi install npm:@tintinweb/pi-subagents' "$tmp/missing"

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

grep -q '^OPTIONAL (Pi): .*defaultJoinMode' "$tmp/initial"
[[ -z "$(find "$project" -name subagents.json)" ]]  # installer never writes Pi extension settings
grep -q 'Keep this rule.' "$project/AGENTS.md"
grep -q 'Keep this too.' "$project/CLAUDE.md"
[[ "$(grep -c '<!-- ALBERT MANAGED START -->' "$project/AGENTS.md")" -eq 1 ]]
[[ "$(grep -c '<!-- ALBERT MANAGED START -->' "$project/CLAUDE.md")" -eq 1 ]]
"$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/again"
assert_absent '^WRITE ' "$tmp/again"

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

# Web access: dry-run is side-effect free, Pi installs only when absent, and
# both harnesses expose the right tools without granting them to Iris.
: > "$MOCK_PI_LOG"
"$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web --dry-run > "$tmp/web-dry"
grep -q '^CHECK Pi web: ' "$tmp/web-dry"
[[ ! -s "$MOCK_PI_LOG" ]]
"$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web > "$tmp/web-initial"
grep -q '^pi install -l npm:pi-web-access$' "$MOCK_PI_LOG"
for role in nora felix vera; do
  grep -q 'ext:pi-web-access/web_search' "$project/.pi/agents/$role.md"
  grep -q 'ext:pi-web-access/fetch_content' "$project/.pi/agents/$role.md"
  grep -q 'ext:pi-web-access/web_enable' "$project/.pi/agents/$role.md"
  grep -q 'WebSearch, WebFetch' "$project/.claude/agents/$role.md"
done
assert_absent 'pi-web-access/' "$project/.pi/agents/iris.md"
assert_absent 'WebSearch' "$project/.claude/agents/iris.md"
grep -q '## Web research' "$project/AGENTS.md"
MOCK_PI_PACKAGES=$'npm:@tintinweb/pi-subagents\nnpm:pi-web-access' \
  "$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web > "$tmp/web-again"
grep -q '^SKIP PI WEB:' "$tmp/web-again"
assert_absent '^WRITE ' "$tmp/web-again"
[[ "$(grep -c '^pi install -l npm:pi-web-access$' "$MOCK_PI_LOG")" -eq 1 ]]

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
for role in albert nora felix vera iris; do
  [[ -f "$project/.agents/agents/$role.md" ]]
done
grep -q '^mainAgent: true$' "$project/.agents/agents/albert.md"
# The Antigravity coordinator is user-visible and must register as quintet, not albert.
grep -q '^name: quintet$' "$project/.agents/agents/albert.md"
assert_absent '^name: albert$' "$project/.agents/agents/albert.md"
for role in nora felix vera iris; do
  grep -q "^name: $role$" "$project/.agents/agents/$role.md"
  grep -q '^subagent: true$' "$project/.agents/agents/$role.md"
  grep -q '^mainAgent: false$' "$project/.agents/agents/$role.md"
  grep -q 'Open with a headline' "$project/.agents/agents/$role.md"
  assert_absent 'Alien Science Ideation is always on' "$project/.agents/agents/$role.md"
  assert_absent 'Always-on Alien Science' "$project/.agents/agents/$role.md"
done
for rule in 'Dynamic workstreams, ownership, and acceptance' 'Exclusive write ownership' 'Independent verification gate' 'Peer messages are coordination, not authority'; do
  grep -q "$rule" "$project/.agents/rules/AGENTS.md"
  grep -q "$rule" "$project/.agents/agents/albert.md"
done
grep -q 'exclusive owned files/path patterns' "$project/.agents/agents/felix.md"
grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$project/.agents/agents/vera.md"
grep -q 'integration acceptance separately' "$project/.agents/agents/iris.md"
grep -q 'coordinator authority' "$project/.agents/agents/nora.md"
[[ "$(grep -c '<!-- ALBERT MANAGED START -->' "$project/.agents/rules/AGENTS.md")" -eq 1 ]]
"$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/agy-project-again"
assert_absent '^WRITE ' "$tmp/agy-project-again"

# Antigravity CLI global-scope install under mocked HOME without touching real $HOME.
# The preview must name the quintet plugin directory before anything is written.
agy_dry_home="$tmp/agy-dry-home"
mkdir -p "$agy_dry_home"
HOME="$agy_dry_home" XDG_CONFIG_HOME="$agy_dry_home/.config" "$root/install.sh" --harness antigravity --scope global --dry-run > "$tmp/agy-global-preview"
grep -q "^WRITE $agy_dry_home/.gemini/config/plugins/quintet/plugin.json$" "$tmp/agy-global-preview"
grep -q "^WRITE $agy_dry_home/.gemini/config/plugins/quintet/agents/albert.md$" "$tmp/agy-global-preview"
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
# Global Antigravity rules and the coordinator agent both carry the full coordinator contract.
grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$agy_global/rules/AGENTS.md"
grep -q '^## Dispatch$' "$agy_global/rules/AGENTS.md"
grep -q '^## Delegation gate$' "$agy_global/rules/AGENTS.md"
grep -q '^## Main-agent personality' "$agy_global/rules/AGENTS.md"
assert_absent 'cross-project policy' "$agy_global/rules/AGENTS.md"
grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$agy_global/agents/albert.md"
grep -q '^## Delegation gate$' "$agy_global/agents/albert.md"
for role in albert nora felix vera iris; do
  [[ -f "$agy_global/agents/$role.md" ]]
done
for role in nora felix vera iris; do
  assert_absent 'Alien Science Ideation is always on' "$agy_global/agents/$role.md"
  assert_absent 'Always-on Alien Science' "$agy_global/agents/$role.md"
done
grep -q '^mainAgent: true$' "$agy_global/agents/albert.md"
grep -q '^name: quintet$' "$agy_global/agents/albert.md"
assert_absent '^name: albert$' "$agy_global/agents/albert.md"
for role in nora felix vera iris; do grep -q "^name: $role$" "$agy_global/agents/$role.md"; done
grep -q 'exclusive owned files/path patterns' "$agy_global/agents/felix.md"
grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$agy_global/agents/vera.md"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-global-again"
assert_absent '^WRITE ' "$tmp/agy-global-again"
assert_absent '^REMOVE ' "$tmp/agy-global-again"
assert_absent '^KEEP ' "$tmp/agy-global-again"

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

# (b) A genuine older layout with nothing user-added still migrates away.
old_home="$tmp/old-home"
old_dir="$old_home/.gemini/config/plugins/albert"
seed_legacy "$old_home"
HOME="$old_home" XDG_CONFIG_HOME="$old_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-old"
grep -q "^REMOVE '$old_dir' (legacy Antigravity plugin, previous project name: every entry is a path this installer rewrites on each update, and the current versions are at '$old_home/.gemini/config/plugins/quintet')" "$tmp/agy-old"
[[ ! -e "$old_dir" ]]
[[ -f "$old_home/.gemini/config/plugins/quintet/plugin.json" && -f "$old_home/.gemini/config/plugins/quintet/agents/felix.md" ]]
assert_absent '^CARRY ' "$tmp/agy-old"
# (f) A rerun after migration is silent and leaves a single plugin directory.
HOME="$old_home" XDG_CONFIG_HOME="$old_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-old-again"
assert_absent '^REMOVE ' "$tmp/agy-old-again"
assert_absent '^KEEP ' "$tmp/agy-old-again"
assert_absent '^WRITE ' "$tmp/agy-old-again"
[[ "$(ls -A "$old_home/.gemini/config/plugins")" == quintet ]]

# (a) User text outside the managed block survives the migration.
carry_home="$tmp/carry-home"
carry_dir="$carry_home/.gemini/config/plugins/albert"
carry_rules="$carry_dir/rules/AGENTS.md"
carry_quintet="$carry_home/.gemini/config/plugins/quintet"
seed_legacy "$carry_home"
printf '\n## House rules\nKeep our bespoke policy.\n' >> "$carry_rules"
HOME="$carry_home" XDG_CONFIG_HOME="$carry_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-carry"
grep -q "^CARRY '$carry_rules' -> '$carry_quintet/rules/AGENTS.md' (your text outside the managed block was preserved)$" "$tmp/agy-carry"
grep -q "^REMOVE '$carry_dir' (legacy Antigravity plugin, previous project name:" "$tmp/agy-carry"
grep -Fqx 'Keep our bespoke policy.' "$carry_quintet/rules/AGENTS.md"
# The carried text must sit outside the managed block, which is rewritten in full.
carry_outside="$(awk '$0=="<!-- ALBERT MANAGED START -->" {exit} {print}' "$carry_quintet/rules/AGENTS.md")"
grep -Fq 'Keep our bespoke policy.' <<< "$carry_outside"
# The carried text sits outside the full coordinator managed block.
grep -q '^## Dynamic workstreams, ownership, and acceptance$' "$carry_quintet/rules/AGENTS.md"
grep -q '^## Dispatch$' "$carry_quintet/rules/AGENTS.md"
assert_absent 'cross-project policy' "$carry_quintet/rules/AGENTS.md"
[[ ! -e "$carry_dir" ]]

# (e) A dry run previews the carry-over and the removal and changes nothing.
dry_home="$tmp/dry-home"
dry_dir="$dry_home/.gemini/config/plugins/albert"
seed_legacy "$dry_home"
printf '\n## House rules\nDry run text.\n' >> "$dry_dir/rules/AGENTS.md"
HOME="$dry_home" XDG_CONFIG_HOME="$dry_home/.config" "$root/install.sh" --harness antigravity --scope global --dry-run > "$tmp/agy-dry-legacy"
grep -q "^CARRY '$dry_dir/rules/AGENTS.md' -> '$dry_home/.gemini/config/plugins/quintet/rules/AGENTS.md' (dry run; your text outside the managed block would be preserved)$" "$tmp/agy-dry-legacy"
grep -q "^REMOVE '$dry_dir' (dry run; legacy Antigravity plugin: every entry is a path this installer rewrites on each update" "$tmp/agy-dry-legacy"
[[ -f "$dry_dir/rules/AGENTS.md" ]]
[[ ! -e "$dry_home/.gemini/config/plugins/quintet" ]]

# Entries this installer does not write stop the migration and are named.
keep_home="$tmp/keep-home"
keep_dir="$keep_home/.gemini/config/plugins/albert"
keep_quintet="$keep_home/.gemini/config/plugins/quintet"
seed_legacy "$keep_home"
mkdir -p "$keep_dir/skills/my-own-skill" "$keep_dir/skills/empty-dir"
printf 'my own skill\n' > "$keep_dir/skills/my-own-skill/SKILL.md"
printf 'my own notes\n' > "$keep_dir/notes.txt"
keep_sum="$(cd "$keep_dir" && find . -type f -exec cksum {} + | sort)"
HOME="$keep_home" XDG_CONFIG_HOME="$keep_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-keep"
grep -q "^KEEP '$keep_dir': legacy Antigravity plugin kept because it holds entries this installer does not write.$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/notes.txt'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/my-own-skill'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/my-own-skill/SKILL.md'$" "$tmp/agy-keep"
grep -q "^  EXTRA '$keep_dir/skills/empty-dir'$" "$tmp/agy-keep"
grep -q "rm -rf -- '$keep_dir'$" "$tmp/agy-keep"
assert_absent '^REMOVE ' "$tmp/agy-keep"
assert_absent '^CARRY ' "$tmp/agy-keep"
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
assert_absent '^REMOVE ' "$tmp/agy-link"
[[ -L "$link_dir/skills/linked" ]]
[[ -f "$link_target/keep.txt" && "$(cat "$link_target/keep.txt")" == 'outside data' ]]

# Unmergeable markers keep the tree and name the file instead of dropping text.
broken_home="$tmp/broken-home"
broken_dir="$broken_home/.gemini/config/plugins/albert"
seed_legacy "$broken_home"
printf '<!-- ALBERT MANAGED START -->\nno end marker\n' > "$broken_dir/rules/AGENTS.md"
HOME="$broken_home" XDG_CONFIG_HOME="$broken_home/.config" "$root/install.sh" --harness antigravity --scope global 2>/dev/null > "$tmp/agy-broken"
grep -q "^KEEP '$broken_dir': '$broken_dir/rules/AGENTS.md' has managed markers that cannot be merged safely, so nothing was removed.$" "$tmp/agy-broken"
[[ -f "$broken_dir/rules/AGENTS.md" ]]

# An incomplete walk never reaches the delete branch.
guard_home="$tmp/guard-home"
guard_dir="$guard_home/.gemini/config/plugins/albert"
seed_legacy "$guard_home"
mkdir -p "$guard_dir/skills/locked"
printf 'x\n' > "$guard_dir/skills/locked/file"
chmod 000 "$guard_dir/skills/locked"
HOME="$guard_home" XDG_CONFIG_HOME="$guard_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-guard" 2>/dev/null
grep -q "^KEEP '$guard_dir': the legacy plugin directory could not be enumerated, so nothing was removed.$" "$tmp/agy-guard"
[[ -f "$guard_dir/plugin.json" ]]
chmod 700 "$guard_dir/skills/locked"

# (c) A third-party plugin named Albert is neither claimed nor reported.
foreign_home="$tmp/foreign-home"
foreign_dir="$foreign_home/.gemini/config/plugins/albert"
mkdir -p "$foreign_dir/agents" "$foreign_dir/rules"
printf '{\n  "name": "albert",\n  "displayName": "Albert"\n}\n' > "$foreign_dir/plugin.json"
printf -- '---\nname: albert\nmainAgent: true\n---\n\nA third-party Albert plugin.\n' > "$foreign_dir/agents/albert.md"
printf '# Third-party rules\n' > "$foreign_dir/rules/AGENTS.md"
HOME="$foreign_home" XDG_CONFIG_HOME="$foreign_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-foreign"
assert_absent '^REMOVE ' "$tmp/agy-foreign"
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
assert_absent '^REMOVE ' "$tmp/agy-partial"
assert_absent '^KEEP ' "$tmp/agy-partial"
[[ -f "$partial_dir/agents/albert.md" ]]

# Project personality sits beside AGENTS.md and changes only the main agent.
cat > "$project/PERSONALITY.md" <<'PERSONA'
Name: Kanade

# Personality
Use short, factual summaries.
PERSONA
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/personalized"
for file in "$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md" "$project/.agents/agents/albert.md"; do
  grep -q 'Name: Kanade' "$file"
  grep -q 'Use short, factual summaries.' "$file"
done
for role in nora felix vera iris; do
  assert_absent 'Name: Kanade' "$project/.pi/agents/$role.md"
  assert_absent 'Name: Kanade' "$project/.claude/agents/$role.md"
  assert_absent 'Name: Kanade' "$project/.agents/agents/$role.md"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/personalized-again"
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
printf 'Name: Rei\n\n# Personality\nKeep it short.\n' > "$custom_source/PERSONALITY.md"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$custom_source/install.sh" --harness antigravity --scope global > "$tmp/renamed-global"
grep -q '"displayName": "Rei"' "$agy_global/plugin.json"
grep -q 'Name: Rei' "$agy_global/agents/albert.md"
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
  [[ "$(grep -Fxc '<!-- ALBERT MANAGED END -->' "$file")" -eq 1 ]]
  assert_absent 'No final newline<!-- ALBERT MANAGED END -->' "$file"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" --dry-run > "$tmp/no-newline-preview"
assert_absent '^WRITE ' "$tmp/no-newline-preview"
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/no-newline-again"
assert_absent '^WRITE ' "$tmp/no-newline-again"

# Reject both reserved marker lines, including CRLF, before writing anything.
for marker in START END; do
  printf 'Name: Kanade\r\n\r\n<!-- ALBERT MANAGED %s -->\r\nMore style.\r\n' "$marker" > "$project/PERSONALITY.md"
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
for file in "$project/AGENTS.md" "$project/CLAUDE.md" "$project/.agents/rules/AGENTS.md" "$project/.agents/agents/albert.md"; do
  grep -qx 'Name: Rei' "$file"
  grep -qx 'Keep CRLF.' "$file"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/crlf-again"
assert_absent '^WRITE ' "$tmp/crlf-again"

echo 'install E2E PASS: harnesses, settings and MCP preservation, web access, personality, scope and idempotence'
