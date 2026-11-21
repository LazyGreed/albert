#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
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
cat > "$tmp/bin/npm" <<'NPM'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$MOCK_PI_LOG"
NPM
chmod +x "$tmp/bin/pi" "$tmp/bin/npm"
export PATH="$tmp/bin:$PATH" MOCK_PI_LOG="$tmp/pi-actions" MOCK_PI_VERSION=1.1.0

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
[[ -f "$project/.pi/skills/ui-ux/SKILL.md" ]]
[[ -f "$project/.pi/skills/verification/SKILL.md" ]]
[[ -f "$project/.claude/skills/verification/SKILL.md" ]]
[[ -x "$project/.pi/skills/verification/scripts/check-ownership.sh" ]]
[[ -x "$project/.claude/skills/verification/scripts/check-ownership.sh" ]]
grep -q 'regression check' "$project/.pi/skills/verification/SKILL.md"
grep -q 'vertical slice' "$project/.claude/skills/verification/SKILL.md"
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
  ! grep -q '^color:' "$project/.claude/agents/$role.md"
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
! grep -q '^WRITE ' "$tmp/again"

# Existing Pi Jev is kept. No second install registration.
MOCK_PI_PACKAGES=$'npm:@tintinweb/pi-subagents\n/path/to/k-jev' \
  "$root/install.sh" --harness pi --scope project --target "$project" --with-jev > "$tmp/jev"
grep -q 'SKIP PI JEV' "$tmp/jev"
! grep -q '^pi install ' "$MOCK_PI_LOG"

# Web opt-in: dry-run is side-effect free, Pi installs only when absent, and
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
! grep -q 'pi-web-access/' "$project/.pi/agents/iris.md"
! grep -q 'WebSearch' "$project/.claude/agents/iris.md"
grep -q '## Web research' "$project/AGENTS.md"
MOCK_PI_PACKAGES=$'npm:@tintinweb/pi-subagents\nnpm:pi-web-access' \
  "$root/install.sh" --harness pi,claude --scope project --target "$project" --with-web > "$tmp/web-again"
grep -q '^SKIP PI WEB:' "$tmp/web-again"
! grep -q '^WRITE ' "$tmp/web-again"
[[ "$(grep -c '^pi install -l npm:pi-web-access$' "$MOCK_PI_LOG")" -eq 1 ]]

# Antigravity CLI project-scope install, parallel workstream contracts, and idempotence.
"$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/agy-project"
[[ -f "$project/.agents/rules/AGENTS.md" && ! -e "$project/.agents/plugin.json" ]]
[[ -f "$project/.agents/skills/verification/SKILL.md" ]]
[[ -x "$project/.agents/skills/verification/scripts/check-ownership.sh" ]]
for role in albert nora felix vera iris; do
  [[ -f "$project/.agents/agents/$role.md" ]]
done
grep -q '^mainAgent: true$' "$project/.agents/agents/albert.md"
for role in nora felix vera iris; do
  grep -q '^subagent: true$' "$project/.agents/agents/$role.md"
  grep -q '^mainAgent: false$' "$project/.agents/agents/$role.md"
  grep -q 'Open with a headline' "$project/.agents/agents/$role.md"
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
! grep -q '^WRITE ' "$tmp/agy-project-again"

# Antigravity CLI global-scope install under mocked HOME without touching real $HOME.
mock_home="$tmp/home"
mkdir -p "$mock_home"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-global"
agy_global="$mock_home/.gemini/config/plugins/albert"
[[ -f "$agy_global/plugin.json" && -f "$agy_global/rules/AGENTS.md" ]]
[[ -x "$agy_global/skills/verification/scripts/check-ownership.sh" ]]
grep -q '"name": "albert"' "$agy_global/plugin.json"
[[ ! -e "$mock_home/.config/quintet/PERSONALITY.md" ]]
grep -q '"displayName": "Albert"' "$agy_global/plugin.json"
grep -q 'Dynamic workstreams, ownership, and acceptance' "$agy_global/rules/AGENTS.md"
for role in albert nora felix vera iris; do
  [[ -f "$agy_global/agents/$role.md" ]]
done
grep -q '^mainAgent: true$' "$agy_global/agents/albert.md"
grep -q 'exclusive owned files/path patterns' "$agy_global/agents/felix.md"
grep -q 'VERDICT PASS|FAIL|NOT RUN|BLOCKED' "$agy_global/agents/vera.md"
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$root/install.sh" --harness antigravity --scope global > "$tmp/agy-global-again"
! grep -q '^WRITE ' "$tmp/agy-global-again"

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
  ! grep -q 'Name: Kanade' "$project/.pi/agents/$role.md"
  ! grep -q 'Name: Kanade' "$project/.claude/agents/$role.md"
  ! grep -q 'Name: Kanade' "$project/.agents/agents/$role.md"
done
"$root/install.sh" --harness pi,claude,antigravity --scope project --target "$project" > "$tmp/personalized-again"
! grep -q '^WRITE ' "$tmp/personalized-again"
grep -q '^Name: Kanade' "$project/PERSONALITY.md"

# Invalid project personality must fail before writes.
printf 'Not a valid header\n' > "$project/PERSONALITY.md"
if "$root/install.sh" --harness antigravity --scope project --target "$project" > "$tmp/invalid" 2>&1; then
  echo 'Invalid personality was accepted' >&2
  exit 1
fi
grep -q 'Personality must start' "$tmp/invalid"
! grep -q '^WRITE ' "$tmp/invalid"

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
for role in nora felix vera iris; do ! grep -q 'Name: Rei' "$agy_global/agents/$role.md"; done
HOME="$mock_home" XDG_CONFIG_HOME="$mock_home/.config" "$custom_source/install.sh" --harness antigravity --scope global > "$tmp/renamed-again"
! grep -q '^WRITE ' "$tmp/renamed-again"

echo 'install E2E PASS: harnesses, personality isolation, scope, idempotence, Jev reuse, web opt-in'
