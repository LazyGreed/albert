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
[[ ! -d "$project/.pi" && ! -d "$project/.claude" ]]
MOCK_PI_VERSION=0.87.1 "$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/version" 2>&1 && exit 1
! test -d "$project/.pi"
grep -q 'Pi >=1.1.0 required' "$tmp/version"
MOCK_PI_PACKAGES='npm:some-other-package' "$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/missing" 2>&1 && exit 1
! test -d "$project/.pi"
grep -q 'pi install npm:@tintinweb/pi-subagents' "$tmp/missing"

"$root/install.sh" --harness pi,claude --scope project --target "$project" > "$tmp/initial"
[[ -f "$project/.pi/agents/felix.md" && -f "$project/.claude/agents/vera.md" ]]
[[ -f "$project/.pi/skills/ui-ux/SKILL.md" ]]
[[ -f "$project/.pi/skills/verification/SKILL.md" ]]
[[ -f "$project/.claude/skills/verification/SKILL.md" ]]
grep -q 'regression check' "$project/.pi/skills/verification/SKILL.md"
grep -q 'vertical slice' "$project/.claude/skills/verification/SKILL.md"
grep -q '^name: felix$' "$project/.pi/agents/felix.md"
grep -q '^prompt_mode: append$' "$project/.pi/agents/felix.md"
grep -q '^disallowed_tools: edit, write$' "$project/.pi/agents/vera.md"
grep -q '^disallowedTools: Write, Edit, NotebookEdit$' "$project/.claude/agents/vera.md"
grep -q 'main session only' "$project/AGENTS.md"
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

echo 'install E2E PASS: prerequisites, dual harness, context, idempotence, Jev reuse'
