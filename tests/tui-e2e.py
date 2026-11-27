#!/usr/bin/env python3
"""Smoke-test the keyboard-driven installer with a real pseudoterminal. Stdlib only."""
from __future__ import annotations

import os
import pty
import select
import subprocess
import tempfile
import time
from pathlib import Path

INSTALL = Path(__file__).resolve().parents[1] / 'install.sh'
ARROW_DOWN = b'\x1b[B'
ESC = b'\x1b'
ENTER = b'\r'
SPACE = b' '


class Session:
    def __init__(self, cwd: Path, *args: str):
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(cwd)
            env = os.environ.copy()
            env['TERM'] = 'xterm'
            os.execve('/usr/bin/env', ['env', 'bash', str(INSTALL), *args], env)
        self.pid, self.fd = pid, fd
        self.read_buffer = b''

    def send(self, data: bytes):
        os.write(self.fd, data)

    def expect(self, marker: bytes, timeout: float = 8.0):
        deadline = time.monotonic() + timeout
        while marker not in self.read_buffer:
            if time.monotonic() >= deadline:
                raise AssertionError(f'Timeout waiting for {marker!r}: {self.read_buffer[-800:]!r}')
            remaining = deadline - time.monotonic()
            if not select.select([self.fd], [], [], min(0.5, max(0.0, remaining)))[0]:
                continue
            try:
                fragment = os.read(self.fd, 8192)
            except OSError as error:
                raise AssertionError(f'Unexpected PTY EOF while waiting for {marker!r}') from error
            if not fragment:
                raise AssertionError(f'Unexpected EOF waiting for {marker!r}')
            self.read_buffer = (self.read_buffer + fragment)[-64000:]

    def finish(self):
        _, status = os.waitpid(self.pid, 0)
        os.close(self.fd)
        assert os.waitstatus_to_exitcode(status) == 0, status


def test_cancel(root: Path):
    session = Session(root)
    session.expect(b'QUINTET  /  INSTALL')
    session.send(ESC)
    session.finish()
    assert not (root / '.pi').exists()


def test_dual_project(root: Path):
    project = root / 'kanade'
    project.mkdir()
    (project / 'AGENTS.md').write_text('Preserve project rules.\n')
    (project / 'CLAUDE.md').write_text('Preserve Claude rules.\n')
    session = Session(root)
    session.expect(b'(*) v2  Dependency graph')
    # Toggle Claude (Pi selected initially); select Project; edit project path.
    session.send(ARROW_DOWN + SPACE + ARROW_DOWN * 3 + ENTER + ARROW_DOWN + ENTER)
    session.expect(b'Project directory [')
    session.send(str(project).encode() + ENTER)
    # Select v1 and leave the default web access enabled, then review.
    session.send(ARROW_DOWN + ENTER + ARROW_DOWN * 3 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Workflow  v1')
    session.expect(b'Web       enabled')
    session.expect(b'Planned')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    assert (project / '.pi/agents/felix.md').is_file()
    assert (project / '.claude/agents/vera.md').is_file()
    assert 'WebSearch, WebFetch' in (project / '.claude/agents/vera.md').read_text()
    assert 'ext:pi-web-access/web_search' in (project / '.pi/agents/nora.md').read_text()
    for filename, rule in (
        ('AGENTS.md', 'Preserve project rules.'),
        ('CLAUDE.md', 'Preserve Claude rules.'),
    ):
        text = (project / filename).read_text()
        assert rule in text
        assert '## Workflow v1\n' in text
        assert '## Workflow v2\n' not in text
        assert text.count('<!-- QUINTET MANAGED START -->') == 1
        assert '<!-- ALBERT MANAGED' not in text


def test_antigravity_project(root: Path):
    project = root / 'antigravity-tui'
    project.mkdir()
    session = Session(root)
    session.expect(b'QUINTET  /  INSTALL')
    # Deselect Pi (focus 0), select Antigravity CLI (focus 2), select Project (focus 4), edit project path (focus 5).
    session.send(SPACE + ARROW_DOWN * 2 + SPACE + ARROW_DOWN * 2 + ENTER + ARROW_DOWN + ENTER)
    session.expect(b'Project directory [')
    session.send(str(project).encode() + ENTER)
    # Walk to Review (focus 9) with the default workflow.
    session.send(ARROW_DOWN * 4 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Harness   antigravity')
    session.expect(b'Scope     project')
    session.expect(b'Workflow  v2')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    text = (project / '.agents/rules/AGENTS.md').read_text()
    assert '## Dynamic workstreams, ownership, and acceptance' in text
    assert '## Workflow v2\n' in text
    assert '## Workflow v1\n' not in text
    assert (project / '.agents/agents/nora.md').is_file()
    assert not (project / '.agents/agents/albert.md').exists()
    assert not (project / '.pi').exists()


def test_global_full(root: Path):
    """Global scope installs the full coordinator contract and personality."""
    session = Session(
        root, '--tui', '--harness', 'pi', '--scope', 'global', '--workflow', 'v1', '--no-web'
    )
    session.expect(b'(*) v1  Coordinator-sequenced handoffs')
    session.send(ARROW_DOWN * 9 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Scope     global')
    session.expect(b'Workflow  v1')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    agents = Path(os.environ['PI_CODING_AGENT_DIR']) / 'AGENTS.md'
    text = agents.read_text()
    assert '# Quintet | cross-project policy' not in text
    for contract in (
        '## Dynamic workstreams, ownership, and acceptance',
        '## Workflow v1\n',
        '## Dispatch',
        '## Delegation gate',
        '## Opt-in Alien Science Ideation',
        'Main-agent personality',
    ):
        assert contract in text


def test_web_disabled(root: Path, *, explicit: bool):
    project = root / ('explicit-no-web' if explicit else 'toggled-no-web')
    project.mkdir()
    args = ('--no-web',) if explicit else ()
    session = Session(project, '--tui', '--harness', 'pi,claude', '--scope', 'project', *args)
    session.expect(b'Cancel')
    initial = b'[ ]' if explicit else b'[x]'
    assert initial + b' Web search and fetch' in session.read_buffer
    if not explicit:
        session.send(ARROW_DOWN * 8 + SPACE)
    session.send(b'j' * (9 if explicit else 1) + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Web       disabled')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    assert 'pi-web-access/' not in (project / '.pi/agents/nora.md').read_text()
    assert 'WebSearch' not in (project / '.claude/agents/vera.md').read_text()


def test_legacy_archive_review(root: Path):
    config = root / '.gemini/config'
    legacy = config / 'plugins/albert'
    (legacy / 'agents').mkdir(parents=True)
    (legacy / 'rules').mkdir()
    (legacy / 'plugin.json').write_text('{"name": "albert", "description": "Quintet"}\n')
    for worker in ('nora', 'felix', 'vera', 'iris'):
        (legacy / f'agents/{worker}.md').write_text(f'Legacy {worker}\n')
    (legacy / 'rules/AGENTS.md').write_text(
        'Keep my legacy rules.\n\n<!-- ALBERT MANAGED START -->\n'
        'Legacy workflow.\n<!-- ALBERT MANAGED END -->\n'
    )
    session = Session(root, '--tui', '--harness', 'antigravity', '--scope', 'global', '--no-web')
    session.expect(b'Cancel')
    session.send(ARROW_DOWN * 9 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Archive the previous Antigravity plugin under ~/.gemini/config/quintet-backups.')
    session.expect(b'Carry user rules into the new plugin before archiving.')
    session.expect(b' more\r\n')
    assert legacy.is_dir()
    assert not (config / 'quintet-backups').exists()
    assert not (config / 'plugins/quintet').exists()
    session.send(ENTER)
    session.expect(b'ARCHIVE ')
    session.expect(b'DONE')
    session.finish()
    assert not legacy.exists()
    backups = list(config.glob('quintet-backups/albert.*/albert'))
    assert len(backups) == 1
    assert (backups[0] / 'agents/felix.md').read_text() == 'Legacy felix\n'
    assert 'Keep my legacy rules.' in (config / 'plugins/quintet/rules/AGENTS.md').read_text()


def test_rule_relocation_review(root: Path):
    project = root / 'relocation-tui'
    project.mkdir()
    args = ('--harness', 'antigravity', '--scope', 'project', '--no-web')
    subprocess.run(['bash', str(INSTALL), *args], cwd=project, check=True, stdout=subprocess.DEVNULL)
    stale = project / '.agents/rules/AGENTS.md.albert-backup-20261127101515-202082'
    original = b'Original user rules, before the installer set up a coordinator.'
    stale.write_bytes(original)
    backups = project / '.quintet-rule-backups'
    session = Session(project, '--tui', *args)
    session.expect(b'Cancel')
    session.send(ARROW_DOWN * 9 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Planned   0 file writes')
    session.expect(b'Old rule backups to relocate: 1 (outside rule discovery).')
    assert stale.read_bytes() == original
    assert not backups.exists()
    session.send(ENTER)
    session.expect(b'RELOCATE RULE ')
    session.expect(b'DONE')
    session.finish()
    assert not stale.exists()
    saved, = backups.glob(f'rule.*/{stale.name}')
    assert saved.read_bytes() == original


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='quintet-tui-') as td:
        root = Path(td)
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        pi = bin_dir / 'pi'
        pi.write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

agent_dir = Path(os.environ['PI_CODING_AGENT_DIR'])
settings = agent_dir / 'settings.json'
config = json.loads(settings.read_text()) if settings.exists() else {'packages': []}
args = sys.argv[1:]


def manifest(source):
    name, version = source[4:].rsplit('@', 1)
    return agent_dir / 'npm' / 'node_modules' / name / 'package.json', name, version


if args == ['--version']:
    print('1.6.1')
elif args == ['list', '--no-approve']:
    print('User packages:')
    for source in config['packages']:
        package, _, _ = manifest(source)
        print(f'  {source}')
        print(f'    {package.parent}')
elif len(args) == 3 and args[0] == 'install' and args[-1] == '--no-approve':
    source = args[1]
    package, name, version = manifest(source)
    package.parent.mkdir(parents=True, exist_ok=True)
    package.write_text(json.dumps({'name': name, 'version': version}))
    config['packages'].append(source)
    settings.write_text(json.dumps(config))
    with (Path(os.environ['HOME']) / 'pi-installs').open('a') as log:
        print(' '.join(args), file=log)
else:
    sys.exit(1)
''')
        pi.chmod(0o755)
        os.environ['PATH'] = f"{bin_dir}:{os.environ['PATH']}"
        os.environ['HOME'] = str(root)
        os.environ['PI_CODING_AGENT_DIR'] = str(root / '.pi/agent')
        test_cancel(root)
        test_web_disabled(root, explicit=True)
        test_web_disabled(root, explicit=False)
        test_global_full(root)
        test_dual_project(root)
        test_antigravity_project(root)
        test_legacy_archive_review(root)
        test_rule_relocation_review(root)
        installs = (root / 'pi-installs').read_text().splitlines()
        assert installs == [
            'install npm:@tintinweb/pi-subagents@0.26.3 --no-approve',
            'install npm:pi-web-access@0.48.0 --no-approve',
        ]
        subagents = Path(os.environ['PI_CODING_AGENT_DIR']) / 'subagents.json'
        assert subagents.read_text() == (
            '{\n'
            '  "maxSubagentDepth": 1,\n'
            '  "defaultJoinMode": "group",\n'
            '  "disableDefaultAgents": true,\n'
            '  "packageAgents": false,\n'
            '  "fallbackSubagent": "none",\n'
            '  "fleetView": false,\n'
            '  "widgetMode": "all"\n'
            '}\n'
        )
    print('TUI E2E PASS: keyboard, review, workflow selection, scopes, web, legacy archive, and rule relocation')
