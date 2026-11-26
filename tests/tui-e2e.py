#!/usr/bin/env python3
"""Smoke-test the keyboard-driven installer with a real pseudoterminal. Stdlib only."""
from __future__ import annotations

import os
import pty
import select
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
    session.expect(b'QUINTET  /  INSTALL')
    # Toggle Claude (Pi selected initially); select Project; edit project path.
    session.send(ARROW_DOWN + SPACE + ARROW_DOWN * 2 + ENTER + ARROW_DOWN + ENTER)
    session.expect(b'Project directory [')
    session.send(str(project).encode() + ENTER)
    # Leave the default web access enabled, then review.
    session.send(ARROW_DOWN * 2 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Web       enabled')
    session.expect(b'Planned')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    assert (project / '.pi/agents/felix.md').is_file()
    assert (project / '.claude/agents/vera.md').is_file()
    assert 'WebSearch, WebFetch' in (project / '.claude/agents/vera.md').read_text()
    assert 'ext:pi-web-access/web_search' in (project / '.pi/agents/nora.md').read_text()
    assert 'Preserve project rules.' in (project / 'AGENTS.md').read_text()
    assert 'Preserve Claude rules.' in (project / 'CLAUDE.md').read_text()
    # The TUI install adds one managed instruction block.
    assert (project / 'AGENTS.md').read_text().count('<!-- ALBERT MANAGED START -->') == 1


def test_global_policy(root: Path):
    """Global scope installs cross-project policy, not the coordinator contract."""
    session = Session(root, '--tui', '--harness', 'pi', '--scope', 'global', '--no-web')
    session.expect(b'Global')
    # Pi and Global are already selected: walk down to Review and install.
    session.send(ARROW_DOWN * 6 + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Scope     global')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    agents = Path(os.environ['PI_CODING_AGENT_DIR']) / 'AGENTS.md'
    text = agents.read_text()
    assert '# Quintet | cross-project policy' in text
    assert '## Coordinator role: project opt-in required' in text
    assert '## Opt-in Alien Science Ideation' in text
    for contract in ('## Dispatch', '## Delegation gate', '## Reporting', 'Main-agent personality'):
        assert contract not in text


def test_web_disabled(root: Path, *, explicit: bool):
    project = root / ('explicit-no-web' if explicit else 'toggled-no-web')
    project.mkdir()
    args = ('--no-web',) if explicit else ()
    session = Session(project, '--tui', '--harness', 'pi,claude', '--scope', 'project', *args)
    session.expect(b'Cancel')
    initial = b'[ ]' if explicit else b'[x]'
    assert initial + b' Web search and fetch' in session.read_buffer
    if not explicit:
        session.send(ARROW_DOWN * 5 + SPACE)
    session.send(b'j' * (6 if explicit else 1) + ENTER)
    session.expect(b'QUINTET  /  REVIEW')
    session.expect(b'Web       disabled')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    assert 'pi-web-access/' not in (project / '.pi/agents/nora.md').read_text()
    assert 'WebSearch' not in (project / '.claude/agents/vera.md').read_text()
    assert not (root / 'pi-installs').exists()


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='albert-tui-') as td:
        root = Path(td)
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        pi = bin_dir / 'pi'
        pi.write_text('''#!/bin/sh
case "$1" in
    --version) echo 1.1.0;;
    list) echo npm:@tintinweb/pi-subagents;;
    install) printf '%s\\n' "$*" >> "$HOME/pi-installs";;
    *) exit 1;;
esac
''')
        pi.chmod(0o755)
        os.environ['PATH'] = f"{bin_dir}:{os.environ['PATH']}"
        os.environ['HOME'] = str(root)
        os.environ['PI_CODING_AGENT_DIR'] = str(root / '.pi/agent')
        test_cancel(root)
        test_web_disabled(root, explicit=True)
        test_web_disabled(root, explicit=False)
        test_global_policy(root)
        test_dual_project(root)
        assert (root / 'pi-installs').read_text() == 'install -l npm:pi-web-access\n'
    print('TUI E2E PASS: cancel, keyboard and review, dual install, global policy scope, web default and opt-out')
