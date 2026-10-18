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
    def __init__(self, cwd: Path):
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(cwd)
            env = os.environ.copy()
            env['TERM'] = 'xterm'
            os.execve('/usr/bin/env', ['env', 'bash', str(INSTALL)], env)
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
    session.expect(b'ALBERT  /  INSTALL')
    session.send(ESC)
    session.finish()
    assert not (root / '.pi').exists()


def test_dual_project(root: Path):
    project = root / 'kanade'
    project.mkdir()
    (project / 'AGENTS.md').write_text('Preserve project rules.\n')
    (project / 'CLAUDE.md').write_text('Preserve Claude rules.\n')
    session = Session(root)
    session.expect(b'ALBERT  /  INSTALL')
    # Toggle Claude (Pi selected initially); select Project; edit project path.
    session.send(ARROW_DOWN + SPACE + ARROW_DOWN * 2 + ENTER + ARROW_DOWN + ENTER)
    session.expect(b'Project directory [')
    session.send(str(project).encode() + ENTER)
    session.send(ARROW_DOWN * 2 + ENTER)
    session.expect(b'ALBERT  /  REVIEW')
    session.expect(b'Planned')
    session.send(ENTER)
    session.expect(b'DONE')
    session.finish()
    assert (project / '.pi/agents/felix.md').is_file()
    assert (project / '.claude/agents/vera.md').is_file()
    assert 'Preserve project rules.' in (project / 'AGENTS.md').read_text()
    assert 'Preserve Claude rules.' in (project / 'CLAUDE.md').read_text()
    # Install is idempotent, even when invoked via TUI.
    assert (project / 'AGENTS.md').read_text().count('<!-- ALBERT MANAGED START -->') == 1


if __name__ == '__main__':
    with tempfile.TemporaryDirectory(prefix='albert-tui-') as td:
        root = Path(td)
        bin_dir = root / 'bin'
        bin_dir.mkdir()
        pi = bin_dir / 'pi'
        pi.write_text('#!/bin/sh\ncase "$1" in --version) echo 1.1.0;; list) echo npm:@tintinweb/pi-subagents;; esac\n')
        pi.chmod(0o755)
        os.environ['PATH'] = f"{bin_dir}:{os.environ['PATH']}"
        test_cancel(root)
        test_dual_project(root)
    print('TUI E2E PASS: escape cancellation, keyboard controls, review, dual-harness install')
