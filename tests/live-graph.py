#!/usr/bin/env python3
"""Plan workflow trials offline or run opt-in Claude Code benchmarks."""

import argparse
from contextlib import redirect_stdout
from hashlib import sha256
from io import StringIO
import json
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import uuid
from unittest.mock import patch


HERE = Path(__file__).resolve().parents[1]
SCENARIOS = ('S1', 'S2', 'S3', 'S4', 'S5', 'S5b')
BRANCH = 'integration/task'
Q0 = '6715d8d52a1d69480be2f2bec778184fb7abd3cf'
SHA = r'[a-f0-9]{7,40}'
REQUIRED_STREAMS = {
    'S1': ('a',), 'S2': ('a', 'b'), 'S3': ('api', 'consumer', 'independent'),
    'S4': ('a', 'b'), 'S5': ('a',), 'S5b': ('api', 'consumer'),
}
MAX_INVOCATIONS = {'S3': 2, 'S5': 3, 'S5b': 2}
USAGE_KEYS = ('input_tokens', 'output_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')


def run(cwd, *args, check=True, **kwargs):
    return subprocess.run(args, cwd=cwd, check=check, capture_output=True, **kwargs)


def git(repo, *args):
    return run(repo, 'git', *args, text=True).stdout.strip()


def ref(repo, name):
    p = run(repo, 'git', 'rev-parse', '--verify', f'{name}^{{commit}}', check=False, text=True)
    return None if p.returncode else p.stdout.strip()


def commit(repo, message):
    git(repo, 'add', '-A')
    git(repo, 'commit', '-qm', message)
    return git(repo, 'rev-parse', 'HEAD')


def put(repo, name, content):
    path = repo / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


def fixture(repo, scenario):
    repo.mkdir()
    git(repo, 'init', '-q', '-b', 'main')
    git(repo, 'config', 'user.name', 'Quintet fixture')
    git(repo, 'config', 'user.email', 'fixture@example.invalid')
    git(repo, 'config', 'core.logAllRefUpdates', 'true')
    put(repo, '.gitignore', '__pycache__/\n')
    put(repo, 'a.py', 'def value(n):\n    return n - 1\n')
    requests = {
        'S1': 'Fix a.value(n) to return n + 1. Use the usual single-stream path.',
        'S2': 'Implement independent streams a and b: a.value(n) returns n + 1; b.value(n) returns n * 2.',
        'S3': 'Streams api, consumer, independent: API returns an error dict and consumer renders its error field. The existing shared/types/error.py field is provisional: the public output must use errorCode, and consumer renders its value. API owns a.py and shared/types/error.py; consumer owns b.py and reads shared/types/**. Independent owns c.py and returns n * 3. If starting consumer early, use the existing shared/types/error.py contract. Before repairing any failed API review, pause after independent passes and report its ref and the initial API verdict. Do not land before the pause.',
        'S4': 'Provide capabilities a and b: a.value(n) returns n + 1 and b.value(n) returns n * 2. Each capability needs registration in the same manifest.txt (one line per capability). Plan as streams a and b with registration part of both requests. Only a, b, or a dedicated manifest stream may commit that file.',
        'S5': 'Fix a.value(n) to return n + 1 in stream a. Pause after independent Vera PASS but BEFORE any landing. Keep the worker checkout intact; report its ref and path.',
        'S5b': 'Streams api and consumer own a.py and b.py. Implement a.encode(n) and b.decode(s) as a positive-integer wire round-trip. Initially follow each module\'s documented encoding and test it in isolation. Run the combined round-trip for n=12 before deciding whether to repair; if the join fails, route the repair and make round-trip work without assuming either isolated format must be kept.',
    }
    if scenario in ('S2', 'S3', 'S4'):
        put(repo, 'b.py', 'def value(n):\n    return n\n')
    if scenario == 'S3':
        put(repo, 'shared/types/error.py', 'KEY = "code"\n')
        put(repo, 'a.py', 'from shared.types.error import KEY\n\ndef error(n):\n    return {KEY: n}\n')
        put(repo, 'b.py', 'def render(error):\n    """Render the value from the public errorCode field."""\n    raise NotImplementedError\n')
        put(repo, 'c.py', 'def value(n):\n    return n\n')
    if scenario == 'S4':
        put(repo, 'manifest.txt', '')
    if scenario == 'S5b':
        put(repo, 'a.py', 'def encode(n):\n    """Initially encode as plain decimal digits."""\n    raise NotImplementedError\n')
        put(repo, 'b.py', 'def decode(s):\n    """Initially decode a string with a required # prefix before the digits."""\n    raise NotImplementedError\n')
    return requests[scenario]


HIDDEN = {
    'S1': 'from a import value; assert [value(n) for n in (-9, 0, 21)] == [-8, 1, 22]',
    'S2': 'import a,b; assert [a.value(4), b.value(-7)] == [5, -14]',
    'S3': 'import a,b,c; assert a.error(29) == {"errorCode": 29}; assert b.render(a.error(29)) == "29"; assert c.value(-2) == -6',
    'S4': 'import a,b; assert [a.value(3), b.value(-6)] == [4, -12]; assert sorted(open("manifest.txt").read().splitlines()) == ["a","b"]',
    'S5': 'from a import value; assert [value(n) for n in (-9, 0, 21)] == [-8, 1, 22]',
    'S5b': 'import a,b; assert all(b.decode(a.encode(n)) == n for n in (1, 12, 107))',
}

SCOPES = {
    'S1': {'a': ('a.py',)}, 'S2': {'a': ('a.py',), 'b': ('b.py',)},
    'S3': {'api': ('a.py', 'shared/types/error.py'), 'consumer': ('b.py',), 'independent': ('c.py',)},
    'S4': {'a': ('a.py', 'manifest.txt'), 'b': ('b.py', 'manifest.txt'), 'manifest': ('manifest.txt',)},
    'S5': {'a': ('a.py',)}, 'S5b': {'api': ('a.py',), 'consumer': ('b.py',), 'seam': ('a.py', 'b.py')},
}


def ancestor(repo, old, new):
    return bool(old and new and not run(repo, 'git', 'merge-base', '--is-ancestor', old, new, check=False).returncode)


def ownership_check(repo, before, after, scope):
    helper = repo / '.claude/skills/verification/scripts/check-ownership.sh'
    return run(repo, 'bash', str(helper), '--base', before, '--head', after, '--repo', str(repo),
               '--', *scope, check=False, text=True)


def ownership(repo, scenario, base, heads):
    violations = []
    known = all(heads.get(stream) for stream in REQUIRED_STREAMS[scenario])
    for stream, head in heads.items():
        if not head:
            continue
        chain = git(repo, 'rev-list', '--first-parent', head).splitlines()
        upstream = {h for s, h in heads.items() if s != stream and h and h != head}
        start = next((sha for sha in chain[1:] if sha == base or sha in upstream), base)
        if not ancestor(repo, base, start) or not ancestor(repo, start, head):
            known = False
            continue
        for row in git(repo, 'rev-list', '--first-parent', '--parents', f'{start}..{head}').splitlines():
            revision, *parents = row.split()
            if not parents:
                known = False
                continue
            checked, _ = authored_patch(repo, parents[0], revision, parents)
            p = ownership_check(repo, parents[0], checked, SCOPES[scenario][stream])
            if p.returncode == 1:
                violations.append({'stream': stream, 'commit': revision, 'check': p.stderr.strip() or p.stdout.strip()})
            elif p.returncode:
                known = False
    return violations, known


def worker_logs(repo):
    root = Path(git(repo, 'rev-parse', '--path-format=absolute', '--git-path', 'logs/refs/heads/wt'))
    return {str(p.relative_to(root)): p.read_text(errors='replace').splitlines()
            for p in sorted(root.rglob('*')) if p.is_file()}


def projected_commit(repo, before, after, paths):
    # Check only the attributable merge patch, without touching a checkout or its real index.
    with tempfile.TemporaryDirectory() as temp:
        env = {**os.environ, 'GIT_INDEX_FILE': str(Path(temp) / 'index')}
        run(repo, 'git', 'read-tree', before, env=env)
        patch = run(repo, 'git', '--literal-pathspecs', 'diff', '--binary', '--no-renames', before, after,
                    '--', *sorted(paths)).stdout
        run(repo, 'git', 'apply', '--cached', input=patch, env=env)
        tree = run(repo, 'git', 'write-tree', env=env, text=True).stdout.strip()
        return git(repo, 'commit-tree', tree, '-p', before, '-m', 'Runner ownership projection')


def authored_patch(repo, before, after, parents):
    paths = changed_paths(repo, before, after)
    if len(parents) < 2:
        return after, paths
    imported = set().union(*(paths - changed_paths(repo, parent, after) for parent in parents[1:]))
    if not imported:
        return after, paths
    own = paths - imported
    return (projected_commit(repo, before, after, own) if own else before), own


def authored_merge(old, parents, action):
    return (len(parents) > 1 and parents[0] == old
            and (action.startswith('commit (merge):')
                 or (action.startswith('merge ') and not action.rpartition(': ')[2].startswith('Fast-forward'))))


def s4_ownership(repo, base, heads, seed, logs):
    known = seed == {} and all(heads.get(s) for s in ('a', 'b'))
    active = {s for s, h in heads.items() if h}
    known &= set(logs) == active
    own, observed, claims, violations, ambiguous = {}, {base}, {}, [], set()
    parents = {}
    zero = '0' * len(base)
    for stream in sorted(set(logs) & set(heads)):
        old = zero
        lines = logs[stream]
        if not lines:
            known = False
        for i, line in enumerate(lines):
            meta, tab, action = line.partition('\t')
            fields = meta.split(' ', 2)
            if not tab or len(fields) != 3 or fields[0] != old or resolve(repo, fields[1]) != fields[1]:
                known = False
                break
            new = fields[1]
            observed.add(new)
            if (i == 0 and not action.startswith('branch: Created from ')
                    or action.lower().startswith(('branch: renamed', 'branch: copied'))):
                known = False
            if new != old and old != zero:
                if new not in parents:
                    parents[new] = git(repo, 'show', '-s', '--format=%P', new).split()
                ps = parents[new]
                edit = ((ps == [old] and action.startswith(('commit:', 'cherry-pick:', 'revert:')))
                        or authored_merge(old, ps, action))
                if action.startswith('commit (amend):') and len(ps) == 1:
                    edit = git(repo, 'show', '-s', '--format=%P', old).split() == ps
                if edit:
                    if new in own and own[new] != (stream, old):
                        ambiguous.add(new)
                        known = False
                    own[new] = (stream, old)
            old = new
        if old != heads[stream]:
            known = False
    # An update not attributable to a writer can be a reset or import of an already attributed revision.
    attributable = own.keys() - ambiguous
    inputs = attributable | {base}
    if observed - inputs:
        known = False
    for sha in sorted(attributable):
        stream, before = own[sha]
        ps = parents[sha]
        if before not in inputs or any(p not in inputs for p in ps):
            known = False
            continue
        checked, paths = authored_patch(repo, before, sha, ps)
        p = ownership_check(repo, before, checked, SCOPES['S4'][stream])
        if p.returncode == 1:
            violations.append({'stream': stream, 'commit': sha, 'check': p.stderr.strip() or p.stdout.strip()})
        elif p.returncode:
            known = False
        for path in sorted(paths):
            previous = claims.setdefault(path, set())
            for other in sorted(previous - {stream}):
                pair = {'streams': sorted((other, stream)), 'path': path}
                if pair not in violations:
                    violations.append(pair)
            previous.add(stream)
    return violations, bool(known), attributable


def s4_integration_ownership(repo, base, final, seed, log, worker_commits):
    known = bool(seed and log[:len(seed)] == seed and seed[-1].split(' ', 2)[1:2] == [base])
    tips = {final} if final else set()
    actions = {}
    previous = base
    if known:
        for line in log[len(seed):]:
            meta, tab, action = line.partition('\t')
            fields = meta.split(' ', 2)
            if not tab or len(fields) != 3 or fields[0] != previous or resolve(repo, fields[1]) != fields[1]:
                known = False
                break
            old, new = fields[:2]
            if old != new:
                actions.setdefault(new, []).append((old, action))
                tips.add(new)
            if action.lower().startswith(('branch: renamed', 'branch: copied')):
                known = False
            previous = new
    known = known and previous == final
    if not tips:
        return [], known

    violations = []
    path = 'manifest.txt'
    # Include every observed tip, not just the final branch, so resets cannot erase a write.
    for row in git(repo, 'rev-list', '--parents', *sorted(tips), '^' + base).splitlines():
        sha, *parents = row.split()
        if not parents:
            known = False
            continue
        if any(path not in changed_paths(repo, parent, sha) for parent in parents):
            # The result takes a parent version verbatim; that parent's history is also checked.
            continue
        moves = actions.get(sha, ())
        if any((action.startswith(('commit:', 'revert:')) and parents[0] == old)
               or (action.startswith('commit (amend):') and git(repo, 'show', '-s', '--format=%P', old).split() == parents)
               or authored_merge(old, parents, action) for old, action in moves):
            violations.append({'stream': BRANCH, 'commit': sha, 'path': path})
        elif sha not in worker_commits or any(action.startswith('cherry-pick:') for _, action in moves):
            known = False
    return violations, known


def changed_paths(repo, before, after):
    return set(run(repo, 'git', 'diff', '--no-renames', '--name-only', '-z', before, after,
                   text=True).stdout.rstrip('\x00').split('\x00')) - {''}


def head_map(repo, scenario):
    return {s: ref(repo, 'wt/' + s) for s in SCOPES[scenario]}


def records(text, status='PASS'):
    pattern = rf'^\s*(?:[-*] )?`?STREAM ([\w-]+); VERDICT {status}; REF ([^@;\s]+@{SHA}); BASE ({SHA}); VERIFIED_AGAINST ([^;\n`]+)(?:;|`?$)'
    return re.findall(pattern, text, re.MULTILINE)


def resolve(repo, evidence):
    sha = evidence.rsplit('@', 1)[-1]
    return ref(repo, sha) if re.fullmatch(SHA, sha) else None


def terminal_result(events):
    return next((e for e in reversed(events) if e.get('type') == 'result'), {})


def text_result(events):
    text = terminal_result(events).get('result')
    return text if isinstance(text, str) else ''


def completion_claim(text):
    text = text.strip()
    pattern = r'^BENCHMARK_OUTCOME (COMPLETE|BLOCKED|REFUSED|PARTIAL)[ \t]*$'
    if text and re.fullmatch(pattern, text.splitlines()[-1]):
        statuses = set(re.findall(pattern, text, re.MULTILINE))
        return (next(iter(statuses)).lower() if len(statuses) == 1 else None, 'COMPLETE' in statuses)
    legacy = re.match(r'^(DONE|BLOCKED|REFUSED|PARTIAL):', text)
    if not legacy:
        return None, None
    status = legacy[1].lower()
    return ('complete', True) if status == 'done' else (status, False)


def trace_metrics(events, *, complete=True):
    usage = [e.get('usage') for e in events if e.get('type') == 'result']
    complete_usage = complete and usage and all(isinstance(row, dict) and all(
        type(row.get(key)) is int and row[key] >= 0 for key in USAGE_KEYS) for row in usage)
    calls, duplicates, seen = [], [], set()
    final = terminal_result(events)
    known = complete and bool(final) and not final.get('is_error')
    for event in events:
        if event.get('type') != 'assistant':
            continue
        message = event.get('message')
        content = message.get('content') if isinstance(message, dict) else None
        if not isinstance(content, list) or not all(isinstance(call, dict) for call in content):
            known = False
            continue
        batch = {}
        for call in content:
            if call.get('type') != 'tool_use' or call.get('name') not in ('Agent', 'Task'):
                continue
            call_id = call.get('id')
            inputs = call.get('input')
            if not isinstance(call_id, str) or not call_id or not isinstance(inputs, dict):
                known = False
                continue
            if call_id in seen:
                continue
            seen.add(call_id)
            if inputs.get('resume'):
                continue
            calls.append(inputs)
            key = json.dumps(inputs, sort_keys=True)
            if key in batch:
                duplicates.append({'id': call_id, 'duplicate_of': batch[key]})
            else:
                batch[key] = call_id
    return {'worker_calls_observed': len(calls) if known else None, 'worker_calls': calls,
            'unnecessary_dispatches': len(duplicates) if known else None,
            'confirmed_duplicate_dispatches': duplicates, 'nested_dispatch_attribution': None,
            'native_invocation_usage': usage,
            'native_turn_tokens': sum(row[key] for row in usage for key in USAGE_KEYS) if complete_usage else None}


def integration_log(repo):
    path = Path(git(repo, 'rev-parse', '--path-format=absolute', '--git-path', 'logs/refs/heads/' + BRANCH))
    return path.read_text().splitlines() if path.is_file() else []


def transitions(repo, base, before, after, final):
    if not before or after[:len(before)] != before or before[-1].split(' ', 2)[1:2] != [base]:
        return None
    previous = base
    heads = []
    for line in after[len(before):]:
        fields = line.split(' ', 2)
        if len(fields) != 3 or fields[0] != previous or resolve(repo, fields[1]) != fields[1]:
            return None
        new = fields[1]
        heads.append(new)
        previous = new
    return heads if previous == final else None


def snapshot(repo, scenario, text):
    workers = {}
    clean = {}
    integration_path = None
    rows = run(repo, 'git', 'worktree', 'list', '--porcelain', '-z', text=True).stdout.split('\x00\x00')
    for row in rows:
        fields = dict(line.split(' ', 1) for line in row.split('\x00') if ' ' in line)
        if 'worktree' not in fields:
            continue
        path = Path(fields['worktree'])
        clean[str(path)] = path.is_dir() and not git(path, 'status', '--porcelain', '--untracked-files=all')
        branch = fields.get('branch', '')
        if branch.startswith('refs/heads/wt/'):
            workers[branch[14:]] = {'head': ref(path, 'HEAD') if path.is_dir() else None,
                                    'clean': clean[str(path)], 'path': str(path)}
        elif branch == 'refs/heads/' + BRANCH:
            integration_path = str(path)
    return {'workers': workers, 'worktree_clean': clean, 'heads': head_map(repo, scenario),
            'base': ref(repo, 'main'), 'integration': ref(repo, BRANCH), 'reflog': integration_log(repo),
            'integration_worktree': integration_path,
            'pass_claims': records(text), 'fail_claims': records(text, 'FAIL'),
            'join_claims': re.findall(rf'^\s*(?:[-*] )?`?JOIN; VERDICT (PASS|FAIL); INTEGRATION_REF ([^;\s]+); BASE ({SHA}); INPUT_REFS ([^;`\n]+)', text, re.MULTILINE),
            'legacy_claims': re.findall(rf'^\s*(?:[-*] )?`?LEGACY_STREAM ([\w-]+); VERDICT (PASS|FAIL); HEAD ({SHA})(?:;|`?$)', text, re.MULTILINE)}


def input_refs(repo, upstream, snap, *, branches):
    upstream = upstream.strip()
    if upstream == 'none':
        return {}
    result = {}
    for item in upstream.split(','):
        name, sep, value = item.strip().partition('=')
        value = value.strip()
        sha = resolve(repo, value)
        if (not sep or name in result or not sha or sha != snap['heads'].get(name)
                or (branches and not value.startswith('wt/' + name + '@'))
                or (not branches and not re.fullmatch(SHA, value))):
            return None
        result[name] = sha
    return result


def matched(repo, snap, base, stream, *, status='PASS', inputs=None, legacy=False):
    worker = snap['workers'].get(stream, {})
    head = worker.get('head')
    if snap['base'] != base or not worker.get('clean') or not head or head != snap['heads'].get(stream):
        return None
    observed = {}
    for verdict in ('PASS', 'FAIL'):
        for name, evidence, base_ref, upstream in snap[verdict.lower() + '_claims']:
            if (name == stream and evidence.startswith('wt/' + stream + '@')
                    and resolve(repo, evidence) == head and resolve(repo, base_ref) == base):
                bound = input_refs(repo, upstream, snap, branches=True)
                if bound is not None and (inputs is None or inputs == bound):
                    observed[verdict] = 'bound claim'
        if verdict not in observed and legacy and not inputs and any(
                name == stream and value == verdict and resolve(repo, sha) == head
                for name, value, sha in snap['legacy_claims']):
            observed[verdict] = 'legacy claim matched to runner snapshot'
    return observed.get(status) if len(observed) == 1 else None


def probe(repo, sha, paths, test):
    if not sha:
        return None
    with tempfile.TemporaryDirectory(prefix='quintet-oracle-') as temp:
        for name in paths:
            p = run(repo, 'git', 'show', f'{sha}:{name}', check=False, text=True)
            if not p.returncode:
                put(Path(temp), name, p.stdout)
        p = run(temp, sys.executable, '-I', '-c', 'import sys; sys.path.insert(0,"."); ' + test,
                check=False, text=True, timeout=10)
        return {'passed': p.returncode == 0, 'exit': p.returncode, 'stderr': p.stderr.strip()}


def s5_history(repo, base, seed, initial, verified, final, mutated, original_claim, verified_claim):
    early = transitions(repo, base, seed, initial['reflog'], initial['integration'])
    interim = transitions(repo, base, seed, verified['reflog'], verified['integration'])
    later = transitions(repo, base, verified['reflog'], final['reflog'], final['integration']) if interim == [] else None
    if early or interim:
        return 'premature integration update'
    if early is None or interim is None or later is None:
        return 'unknown integration history'
    if not (mutated and original_claim and verified_claim):
        return 'missing mutation or matched verdict'
    if any(head != verified['heads']['a'] for head in later):
        return 'integration update does not match pre-landing approval'
    return 'matches pre-landing approval' if later else 'no landing'


def verdict_bindings(repo, scenario, snap):
    rows = []
    for status in ('PASS', 'FAIL'):
        rows.extend((f'wt/{stream}', status, evidence, base, inputs)
                    for stream, evidence, base, inputs in snap[status.lower() + '_claims'])
    rows.extend((BRANCH, status, evidence, base, inputs)
                for status, evidence, base, inputs in snap['join_claims'])
    rows.extend((f'wt/{stream}', status, evidence, None, None)
                for stream, status, evidence in snap['legacy_claims'])
    observed = []
    actual_inputs = {stream: head for stream, head in snap['heads'].items() if head}
    for branch, status, evidence, base, inputs in rows:
        join = branch == BRANCH
        stream = branch.removeprefix('wt/')
        head = snap['integration'] if join else snap['heads'].get(stream)
        stale, unsupported = [], []

        def compare(field, value, current, expected_branch=None):
            sha = resolve(repo, value)
            if (not current or not sha or (expected_branch and not value.startswith(expected_branch + '@'))
                    or (expected_branch is None and not re.fullmatch(SHA, value))):
                unsupported.append(field)
            elif sha != current:
                stale.append(field)

        if base is None:
            compare('HEAD', evidence, head)
        else:
            compare('INTEGRATION_REF' if join else 'REF', evidence, head, branch)
            compare('BASE', base, snap['base'])
            names = set()
            for item in inputs.strip().split(',') if inputs.strip() != 'none' else ():
                name, sep, value = item.strip().partition('=')
                if not sep or not name or name in names:
                    unsupported.append('INPUT_REFS' if join else 'VERIFIED_AGAINST')
                    continue
                names.add(name)
                compare(name, value.strip(), actual_inputs.get(name), None if join else 'wt/' + name)
            if join:
                required = set(REQUIRED_STREAMS[scenario]) | actual_inputs.keys()
            else:
                required = {'api'} if (scenario, stream) == ('S3', 'consumer') else set()
            unsupported.extend(sorted(required - names))
        observed.append({'branch': branch, 'verdict': status, 'ref': evidence, 'base': base, 'inputs': inputs,
                         'stale_fields': stale, 'unsupported_fields': unsupported, 'provenance_known': None})
    return observed


def join_binding(snap, base, bindings, status):
    if not snap['integration'] or snap['base'] != base:
        return False
    bound = {row['verdict'] for row in bindings
             if row['branch'] == BRANCH and not row['stale_fields'] and not row['unsupported_fields']}
    return bound == {status}


def worktree_ownership(repo, snap, scopes):
    helper = repo / '.claude/skills/verification/scripts/check-ownership.sh'
    checks = [(stream, worker['head'], worker['path'], scopes[stream])
              for stream, worker in snap['workers'].items() if stream in scopes and not worker['clean']]
    path = snap['integration_worktree']
    if path and not snap['worktree_clean'].get(path):
        checks.append((BRANCH, snap['integration'], path, sorted(set().union(*scopes.values()))))
    violations, known = [], True
    for stream, head, path, scope in checks:
        if not head:
            known = False
            continue
        p = run(repo, 'bash', str(helper), '--base', head, '--worktree', path, '--', *scope, check=False, text=True)
        if p.returncode == 1:
            violations.append({'stream': stream, 'check': p.stderr.strip() or p.stdout.strip(), 'worktree': path})
        elif p.returncode:
            known = False
    return violations, known


def inspect(repo, scenario, base, checkpoint, events, *, legacy=False):
    text = text_result(events)
    snap = snapshot(repo, scenario, text)
    final, heads = snap['integration'], snap['heads']
    paths = sorted(set().union(*SCOPES[scenario].values()))
    hidden = probe(repo, final, paths, HIDDEN[scenario])
    supported = {stream for stream in heads if matched(
        repo, snap, base, stream, inputs={'api': heads['api']} if (scenario, stream) == ('S3', 'consumer') else None)}
    joined = all(head != base and ancestor(repo, base, head) and ancestor(repo, head, final)
                 for stream, head in heads.items() if stream in REQUIRED_STREAMS[scenario] or head)
    if scenario == 'S4':
        logs = worker_logs(repo)
        violations, workers_known, worker_commits = s4_ownership(repo, base, heads, checkpoint.get('seed_worker_reflogs'), logs)
        integration_violations, integration_known = s4_integration_ownership(
            repo, base, final, checkpoint.get('seed_reflog', []), snap['reflog'], worker_commits)
        violations += integration_violations
        ownership_attribution_known = workers_known and integration_known
    else:
        violations, ownership_attribution_known = ownership(repo, scenario, base, heads)
    worktree_violations, worktree_known = worktree_ownership(repo, snap, SCOPES[scenario])
    violations.extend(worktree_violations)
    ownership_attribution_known &= bool(final) and worktree_known
    if final:
        p = ownership_check(repo, base, final, paths)
        if p.returncode == 1:
            violations.append({'stream': BRANCH, 'check': p.stderr.strip() or p.stdout.strip()})
        elif p.returncode:
            ownership_attribution_known = False
    outcome, claimed = completion_claim(text)
    acceptance = {'base_unchanged': snap['base'] == base,
                  'required_heads_landed': joined,
                  'integration_clean': snap['worktree_clean'].get(snap['integration_worktree']),
                  'observed_worktrees_clean': all(snap['worktree_clean'].values()),
                  'hidden_check': hidden['passed'] if hidden else None,
                  'ownership_check': False if violations else True if ownership_attribution_known else None}
    accepted = outcome == 'complete' and not terminal_result(events).get('is_error') and all(acceptance.values())
    bindings = {'final': verdict_bindings(repo, scenario, snap)}
    for stage in ('initial', 'pre_landing'):
        if stage in checkpoint:
            bindings[stage] = verdict_bindings(repo, scenario, checkpoint[stage])
    reported = [row for rows in bindings.values() for row in rows]
    supplied_stale = sum(bool(row['stale_fields']) for row in reported)
    stale_evidence = supplied_stale if supplied_stale or (reported and all(not row['unsupported_fields'] for row in reported)) else None
    result = {'accepted': accepted, 'completion_outcome': outcome, 'acceptance_checks': acceptance,
              'unsupported_completion_claims': int(claimed and not accepted) if claimed is not None else None,
              'base': base, 'integration': final, 'hidden_probe': hidden,
              'heads': heads, 'worktree_clean': snap['worktree_clean'],
              'ownership_violations': violations if violations or ownership_attribution_known else None,
              'ownership_attribution_known': ownership_attribution_known,
              'stale_evidence': stale_evidence, 'reported_verdict_bindings': bindings,
              'structured_pass_streams': sorted(supported), 'checkpoint': checkpoint,
              'raw_session_evidence': 'separate JSONL', **trace_metrics(events)}
    if scenario == 'S4':
        result['worker_reflogs'] = logs
        result['integration_reflog'] = snap['reflog']
    if scenario == 'S3':
        initial = checkpoint.get('initial')
        seeded = initial and checkpoint.get('no_early_integration') is True and initial.get('api_fail') and initial.get('independent_pass')
        history = transitions(repo, base, checkpoint.get('seed_reflog', []), snap['reflog'], final)
        result['initial_api_landed_before_repair'] = (any(ancestor(repo, initial['heads']['api'], h)
                                                       and not ancestor(repo, heads['api'], h) for h in history)
                                                       if seeded and history is not None and heads['api'] != initial['heads']['api'] else None)
        result['independent_unchanged'] = heads['independent'] == initial['heads']['independent'] if seeded else None
        seeded = (seeded and result['initial_api_landed_before_repair'] is False and heads['api']
                  and heads['api'] != initial['heads']['api'])
        result['consumer_bound_to_final_api'] = (bool(matched(repo, snap, base, 'consumer', inputs={'api': heads['api']}))
                                                 if seeded and heads['api'] and not legacy else None)
        if seeded and legacy and heads['api']:
            # Q0 is eligible for positive proof, but absence of an unrequired binding is unknown.
            result['consumer_bound_to_final_api'] = True if matched(repo, snap, base, 'consumer', inputs={'api': heads['api']}) else None
    if scenario == 'S5':
        result['observed_integration_history'] = checkpoint.get('history')
        result['stale_landing'] = (True if checkpoint.get('history') in ('premature integration update',
                                    'integration update does not match pre-landing approval') else None)
        result['landing_time_cleanliness_and_verdict_provenance'] = None
    if scenario == 'S5b':
        result['observed_first_join_failure'] = checkpoint.get('observed_first_join_failure')
        result['repair_rounds'] = None  # Visible Agent calls alone do not identify fix/review pairs.
        result['final_join_binding'] = join_binding(snap, base, bindings['final'], 'PASS')
        first = result['observed_first_join_failure']
        result['repair_inputs_refreshed'] = (bool(result['accepted'] and result['final_join_binding']
                                               and {k: v for k, v in heads.items() if v} != first['inputs'])
                                            if first and first['observed'] else None)
    return result


def read_events(log):
    events = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
    if not all(isinstance(event, dict) for event in events):
        raise ValueError(f'expected JSON event objects in {log}')
    return events


def latency_metrics(timing, *, censored=False):
    seconds = timing[-1]['ended_monotonic_seconds'] - timing[0]['started_monotonic_seconds'] if timing else None
    return {'wall_latency_seconds': seconds, 'wall_latency_censored': censored if timing else None,
            'native_invocations': timing}


def invoke(repo, args, prompt, log, timing, session=None):
    command = ['claude', '--print', '--verbose', '--output-format', 'stream-json', '--model', args.model,
               '--max-budget-usd', str(args.budget), '--permission-mode', 'acceptEdits', '--setting-sources', 'project', '--strict-mcp-config']
    if session:
        command += ['--resume', session]
    with log.open('w') as out, log.with_suffix('.stderr').open('w') as err:
        started = time.monotonic()
        exit_code = None
        try:
            completed = subprocess.run([*command, prompt], cwd=repo, stdout=out, stderr=err, timeout=args.timeout)
            exit_code = completed.returncode
        finally:
            timing.append({'log': log.name, 'started_monotonic_seconds': started,
                           'ended_monotonic_seconds': time.monotonic(), 'exit': exit_code})
            put(log.parent, 'timing.json', json.dumps(timing, indent=2) + '\n')
    events = read_events(log)
    result = [e for e in events if e.get('type') == 'result']
    if completed.returncode or len(result) != 1 or result[0].get('is_error'):
        raise RuntimeError(f'Claude run failed; inspect {log} and {log.with_suffix(".stderr")}')
    return events, result[0].get('session_id')


def blocked_result(out, error, scenario):
    timing_file = out / 'timing.json'
    timing = json.loads(timing_file.read_text()) if timing_file.is_file() else []
    events = []
    complete = bool(timing)
    for invocation in timing:
        try:
            stage = read_events(out / invocation['log'])
        except (OSError, ValueError):
            complete = False
            continue
        complete &= sum(event.get('type') == 'result' for event in stage) == 1
        events.extend(stage)
    terminal_log = 'resume.jsonl' if scenario in MAX_INVOCATIONS else 'initial.jsonl'
    terminal_seen = (complete and timing[-1]['log'] == terminal_log and timing[-1]['exit'] == 0
                     and not terminal_result(events).get('is_error'))
    outcome, claimed = completion_claim(text_result(events)) if terminal_seen else (None, None)
    return {'accepted': False, 'blocked': str(error), 'completion_outcome': outcome,
            'unsupported_completion_claims': int(claimed) if claimed is not None else None,
            'ownership_violations': None, 'ownership_attribution_known': False, 'stale_evidence': None,
            **trace_metrics(events, complete=complete), **latency_metrics(timing, censored=not terminal_seen)}


def initial_join_failure(repo, base, seed, snap):
    api, consumer = (snap['heads'][s] for s in ('api', 'consumer'))
    history = transitions(repo, base, seed, snap['reflog'], snap['integration'])
    if not (api and consumer and api != consumer and history and not snap['heads']['seam'] and snap['base'] == base):
        return None
    actual = snap['integration']
    if (set(git(repo, 'show', '-s', '--format=%P', actual).split()) != {api, consumer}
            or any(ancestor(repo, api, head) and ancestor(repo, consumer, head) for head in history[:-1])
            or changed_paths(repo, api, actual) != {'b.py'} or changed_paths(repo, consumer, actual) != {'a.py'}
            or changed_paths(repo, base, api) != {'a.py'} or changed_paths(repo, base, consumer) != {'b.py'}):
        return None
    isolated = [probe(repo, api, ('a.py',), 'from a import encode; assert encode(12) == "12"'),
                probe(repo, consumer, ('b.py',), 'from b import decode; assert decode("#12") == 12')]
    observed = probe(repo, actual, ('a.py', 'b.py'), HIDDEN['S5b'])
    bindings = verdict_bindings(repo, 'S5b', snap)
    return {'inputs': {'api': api, 'consumer': consumer}, 'integration': actual,
            'isolated': isolated, 'join': observed, 'reported_binding': join_binding(snap, base, bindings, 'FAIL'),
            'observed': all(p['passed'] for p in isolated) and observed['exit'] == 1}


def install_command(source, target, workflow=None):
    # Historical Q0 install.sh rejects an unknown --workflow flag. Omit it unless a trial selects one.
    command = ['bash', str(Path(source) / 'install.sh'), '--harness', 'claude', '--scope', 'project', '--target', str(target)]
    if workflow is not None:
        if workflow not in ('v1', 'v2'):
            raise ValueError(f'workflow must be v1 or v2, not {workflow!r}')
        command.extend(('--workflow', workflow))
    command.extend(('--no-tui', '--no-web'))
    return tuple(command)


def trial(source, out, args, scenario, *, legacy, workflow=None):
    if getattr(args, 'same_revision', False) and workflow not in ('v1', 'v2'):
        raise ValueError('same-revision trial requires workflow v1 or v2')
    start = time.monotonic()
    repo = out / 'repo'
    request = fixture(repo, scenario)
    run(repo, *install_command(source, repo, workflow))
    base = commit(repo, 'Fixture baseline and installed instructions')
    git(repo, 'update-ref', '--create-reflog', '-m', 'runner seed ' + uuid.uuid4().hex, 'refs/heads/' + BRANCH, base)
    seed = integration_log(repo)
    if scenario == 'S5b':
        request += ' Pause immediately after the first joined check, before any repair. Keep the two original worker refs and report the join verdict.'
    prompt = (f'{request}\nKeep main unchanged, do not push. The runner already created {BRANCH} at main. Land work by Git ancestry on it, '
              'with stream branches wt/<stream-id> in isolated worktrees when using multiple writers. For S1 keep the single stream '
              'on wt/a, then fast-forward the integration branch. Output actual worker verdict lines and join evidence, not example or invented values. '
              'If a verdict has revision/base/input bindings, include them verbatim. Otherwise include an observed legacy result as one line, '
              'LEGACY_STREAM <id>; VERDICT <PASS|FAIL>; HEAD <sha actually reviewed>, only if the reviewed SHA is known. '
              'For a bound join report, use one line: '
              'JOIN; VERDICT <status>; INTEGRATION_REF <ref>; BASE <sha>; INPUT_REFS <stream=sha,...>. Run focused checks. '
              'Leave the final integration branch checked out and clean for the runner to inspect. '
              'End the final reply with exactly one line of the form BENCHMARK_OUTCOME <status>, '
              'using COMPLETE, BLOCKED, REFUSED, or PARTIAL for the actual outcome.\n'
              f'Scenario: {scenario}.')
    checkpoint = {'seed_reflog': seed}
    if scenario == 'S4':
        checkpoint['seed_worker_reflogs'] = worker_logs(repo)
        if checkpoint['seed_worker_reflogs'] or any(head_map(repo, scenario).values()):
            raise ValueError('S4 requires a fresh fixture without worker refs or reflogs')
    timing = []
    events, session = invoke(repo, args, prompt, out / 'initial.jsonl', timing)
    if scenario in ('S3', 'S5', 'S5b'):
        text = text_result(events)
        initial = checkpoint['initial'] = snapshot(repo, scenario, text)
        history = transitions(repo, base, seed, initial['reflog'], initial['integration'])
        checkpoint['no_early_integration'] = None if history is None else not history
        if scenario == 'S3':
            api, independent = (initial['heads'][s] for s in ('api', 'independent'))
            initial['api_probe'] = probe(repo, api, SCOPES[scenario]['api'], 'from a import error; assert error(29) == {"errorCode": 29}')
            initial['independent_probe'] = probe(repo, independent, ('c.py',), 'from c import value; assert value(-2) == -6')
            if initial['api_probe'] and 'AssertionError' in initial['api_probe']['stderr']:
                initial['api_fail'] = matched(repo, initial, base, 'api', status='FAIL', inputs={}, legacy=legacy)
            if initial['independent_probe'] and initial['independent_probe']['passed']:
                initial['independent_pass'] = matched(repo, initial, base, 'independent', inputs={}, legacy=legacy)
        if scenario == 'S5b':
            checkpoint['observed_first_join_failure'] = initial_join_failure(repo, base, seed, initial)
        if scenario == 'S5':
            original = initial['heads']['a']
            initial['probe'] = probe(repo, original, ('a.py',), HIDDEN['S5'])
            if initial['probe'] and initial['probe']['passed']:
                initial['matched_pass'] = matched(repo, initial, base, 'a', inputs={}, legacy=legacy)
            if history == [] and initial.get('matched_pass'):
                path = Path(initial['workers']['a']['path'])
                put(path, 'a.py', 'def value(n):\n    return -999\n')
                checkpoint['mutated'] = commit(path, 'Fixture: mutate verified stream')
        put(out, 'checkpoint.json', json.dumps(checkpoint, indent=2) + '\n')
        if not session:
            raise RuntimeError('native session ID missing; cannot resume')
        if scenario == 'S5' and checkpoint.get('mutated'):
            extra, session = invoke(repo, args, 'Resume verification. Pause again before any landing, with the clean current worker checkout and actual verifier verdict.', out / 'pre-landing.jsonl', timing, session)
            events.extend(extra)
            verified = checkpoint['pre_landing'] = snapshot(repo, scenario, text_result(extra))
            approved = verified['heads']['a']
            verified['probe'] = probe(repo, approved, ('a.py',), HIDDEN['S5'])
            if approved not in (original, checkpoint['mutated']) and verified['probe'] and verified['probe']['passed']:
                verified['matched_pass'] = matched(repo, verified, base, 'a', inputs={}, legacy=legacy)
            put(out, 'checkpoint.json', json.dumps(checkpoint, indent=2) + '\n')
            if not session:
                raise RuntimeError('native session ID missing at second pause')
        extra, _ = invoke(repo, args, 'Resume the original task. Verify the current evidence before proceeding and report the final observed evidence and BENCHMARK_OUTCOME line.', out / 'resume.jsonl', timing, session)
        events.extend(extra)
        if scenario == 'S5':
            final = checkpoint['final'] = snapshot(repo, scenario, text_result(extra))
            verified = checkpoint.get('pre_landing', initial)
            checkpoint['history'] = s5_history(repo, base, seed, initial, verified, final, checkpoint.get('mutated'),
                                               initial.get('matched_pass'), verified.get('matched_pass'))
    result = inspect(repo, scenario, base, checkpoint, events, legacy=legacy)
    result.update(latency_metrics(timing))
    result['seconds'] = round(time.monotonic() - start, 2)
    return result


def fixture_result(text='BENCHMARK_OUTCOME COMPLETE', usage=None):
    return [{'type': 'result', 'result': text, 'usage': usage}]


def prove_trace_metrics():
    def agent(call_id, **inputs):
        return {'type': 'tool_use', 'name': 'Agent', 'id': call_id, 'input': inputs}

    def batch(*calls):
        return {'type': 'assistant', 'message': {'content': list(calls)}}

    usage = dict(zip(USAGE_KEYS, (10, 3, 5, 12)))
    work = {'subagent_type': 'felix', 'prompt': 'Repair a'}
    events = [batch(agent('one', **work), agent('two', **work), agent('three', resume='one')),
              *fixture_result(usage=usage), batch(agent('four', **work)), *fixture_result(usage=usage)]
    metrics = trace_metrics(events)
    assert metrics['native_turn_tokens'] == 60 and metrics['worker_calls_observed'] == 3
    assert metrics['unnecessary_dispatches'] == 1 and metrics['nested_dispatch_attribution'] is None
    assert metrics['confirmed_duplicate_dispatches'] == [{'id': 'two', 'duplicate_of': 'one'}]
    partial = trace_metrics([*events, *fixture_result(usage={'input_tokens': 1})])
    assert partial['native_turn_tokens'] is None
    assert trace_metrics(fixture_result(usage={**usage, 'output_tokens': True}))['native_turn_tokens'] is None
    assert trace_metrics(fixture_result())['unnecessary_dispatches'] == 0
    assert trace_metrics([batch(agent(None, **work)), *fixture_result()])['unnecessary_dispatches'] is None
    assert trace_metrics([{'type': 'assistant'}, *fixture_result()])['worker_calls_observed'] is None
    assert trace_metrics([])['worker_calls_observed'] is None
    assert trace_metrics(events, complete=False)['native_turn_tokens'] is None

    with tempfile.TemporaryDirectory() as temp:
        out = Path(temp)
        timing = []
        args = argparse.Namespace(model='fixture-model', budget=1, timeout=60)

        def fake_run(command, *, cwd, stdout, stderr, timeout):
            assert command[0] == 'claude' and timeout == 60
            event = fixture_result(usage=usage)[0]
            print(json.dumps({**event, 'session_id': 'fixture-session'}), file=stdout)
            return subprocess.CompletedProcess(command, 0)

        with patch.object(subprocess, 'run', side_effect=fake_run), patch.object(time, 'monotonic', side_effect=(10, 12, 20, 26)):
            _, session = invoke(out, args, 'initial fixture prompt', out / 'initial.jsonl', timing)
            invoke(out, args, 'resume fixture prompt', out / 'resume.jsonl', timing, session)
        actual = latency_metrics(timing)
        assert actual['wall_latency_seconds'] == 16 and actual['wall_latency_censored'] is False
        assert json.loads((out / 'timing.json').read_text()) == timing
        result = blocked_result(out, 'fixture scoring error', 'S5')
        assert result['wall_latency_seconds'] == 16 and result['native_turn_tokens'] == 60
        assert result['unsupported_completion_claims'] == 1 and result['completion_outcome'] == 'complete'
        put(out, 'resume.jsonl', 'incomplete JSON')
        result = blocked_result(out, 'fixture interrupted trace', 'S5')
        assert result['wall_latency_censored'] is True and result['native_turn_tokens'] is None
        assert result['unsupported_completion_claims'] is None
    assert latency_metrics([])['wall_latency_seconds'] is None


def self_test():
    assert records('PASS') == []
    sample = 'STREAM b; VERDICT PASS; REF wt/b@1234567; BASE abcdef1; VERIFIED_AGAINST a=wt/a@abcdef2; ACCEPT done'
    assert records(sample) == [('b', 'wt/b@1234567', 'abcdef1', 'a=wt/a@abcdef2')]
    prove_same_revision()
    prove_trace_metrics()
    with tempfile.TemporaryDirectory() as tmp:
        for scenario in SCENARIOS:
            repo = Path(tmp) / scenario
            fixture(repo, scenario)
            run(repo, 'bash', str(HERE / 'install.sh'), '--harness', 'claude', '--scope', 'project', '--target', str(repo), '--no-tui', '--no-web')
            base = commit(repo, 'Baseline')
            assert not inspect(repo, scenario, base, {}, [])['accepted']
            git(repo, 'checkout', '-qb', BRANCH)
            git(repo, 'branch', 'wt/a')
            assert not inspect(repo, scenario, base, {}, [])['accepted']
            if scenario == 'S1':
                put(repo, 'a.py', 'def value(n):\n    return n + 1\n')
                new = commit(repo, 'Fix')
                git(repo, 'branch', '-f', 'wt/a', new)
                for text, outcome, accepted, unsupported in (
                        ('BENCHMARK_OUTCOME COMPLETE', 'complete', True, 0),
                        ('DONE: fix landed', 'complete', True, 0),
                        ('BENCHMARK_OUTCOME BLOCKED', 'blocked', False, 0),
                        ('BENCHMARK_OUTCOME REFUSED', 'refused', False, 0),
                        ('BENCHMARK_OUTCOME PARTIAL', 'partial', False, 0),
                        ('BENCHMARK_OUTCOME COMPLETE\nBENCHMARK_OUTCOME BLOCKED', None, False, 1),
                        ('No outcome marker.', None, False, None),
                        ('Example:\n```\nBENCHMARK_OUTCOME COMPLETE\n```', None, False, None)):
                    result = inspect(repo, scenario, base, {}, fixture_result(text))
                    assert (result['completion_outcome'], result['accepted'], result['unsupported_completion_claims']) == (
                        outcome, accepted, unsupported), result
                put(repo, 'untracked', 'untracked')
                result = inspect(repo, scenario, base, {}, fixture_result())
                assert not result['accepted'] and result['unsupported_completion_claims'] == 1
                assert not result['acceptance_checks']['integration_clean']
                assert len(result['ownership_violations']) == 1 and 'untracked' in result['ownership_violations'][0]['check']
            if scenario == 'S2':
                git(repo, 'switch', 'wt/a')
                put(repo, 'a.py', 'def value(n): return n + 1\n')
                put(repo, 'unowned.txt', 'out of scope\n')
                unowned = commit(repo, 'A writes out of scope')
                (repo / 'unowned.txt').unlink()
                commit(repo, 'A removes out-of-scope file')
                git(repo, 'switch', '-qc', 'wt/b', base)
                put(repo, 'b.py', 'def value(n): return n * 2\n')
                commit(repo, 'B implements its capability')
                git(repo, 'switch', BRANCH)
                git(repo, 'merge', '--ff-only', 'wt/a')
                git(repo, 'merge', '--no-edit', 'wt/b')
                result = inspect(repo, scenario, base, {}, fixture_result())
                assert result['hidden_probe']['passed'] and result['acceptance_checks']['required_heads_landed']
                assert not result['accepted'] and result['unsupported_completion_claims'] == 1
                violations = result['ownership_violations']
                assert {v['stream'] for v in violations} == {'a'} and any(v['commit'] == unowned for v in violations)
        repo = Path(tmp) / 'S5'
        base = ref(repo, 'main')
        wt = Path(tmp) / 'S5-worker'
        git(repo, 'branch', '-D', 'wt/a')
        git(repo, 'worktree', 'add', '-b', 'wt/a', str(wt), base)
        def checked(head):
            return snapshot(repo, 'S5', f'STREAM a; VERDICT PASS; REF wt/a@{head}; BASE {base}; VERIFIED_AGAINST none')

        seed = integration_log(repo)
        put(wt, 'a.py', 'def value(n):\n    return n + 1\n')
        original = commit(wt, 'Fix')
        initial = checked(original)
        assert matched(repo, initial, base, 'a', inputs={})
        legacy_claim = snapshot(repo, 'S5', f'LEGACY_STREAM a; VERDICT PASS; HEAD {original}')
        assert not matched(repo, legacy_claim, base, 'a', inputs={})
        assert matched(repo, legacy_claim, base, 'a', inputs={}, legacy=True)
        assert not matched(repo, legacy_claim, original, 'a', inputs={}, legacy=True)
        put(wt, 'dirty', 'untracked')
        assert not matched(repo, checked(original), base, 'a', inputs={})
        (wt / 'dirty').unlink()
        put(wt, 'a.py', 'def value(n):\n    return -999\n')
        mutated = commit(wt, 'Mutation')
        put(wt, 'a.py', 'def value(n):\n    return n + 1\n')
        repaired = commit(wt, 'Repair')
        verified = checked(repaired)
        assert matched(repo, verified, base, 'a', inputs={})
        git(repo, 'merge', '--ff-only', 'wt/a')
        safe = checked(repaired)
        assert s5_history(repo, base, seed, initial, verified, safe, mutated, True, True) == 'matches pre-landing approval'
        assert inspect(repo, 'S5', base, {'history': 'matches pre-landing approval'}, [])['stale_landing'] is None
        git(repo, 'reset', '--hard', base)  # Disposable fixture only.
        restored = integration_log(repo)
        initial['reflog'] = verified['reflog'] = restored
        git(repo, 'merge', '--ff-only', mutated)
        git(repo, 'merge', '--ff-only', repaired)
        unsafe = checked(repaired)
        history = s5_history(repo, base, restored, initial, verified, unsafe, mutated, True, True)
        assert history == 'integration update does not match pre-landing approval'
        assert inspect(repo, 'S5', base, {'history': history}, [])['stale_landing'] is True
        assert s5_history(repo, base, seed, initial, verified, unsafe, mutated, True, True) == 'premature integration update'
        assert s5_history(repo, base, restored, initial, verified, {**unsafe, 'reflog': []}, mutated, True, True) == 'unknown integration history'
        repo = Path(tmp) / 'S4'
        base = ref(repo, 'main')
        git(repo, 'branch', '-D', 'wt/a')  # Remove the generic acceptance-test branch before the S4 seed.
        seed = worker_logs(repo)
        assert seed == {}
        checkpoint = {'seed_worker_reflogs': seed, 'seed_reflog': integration_log(repo)}

        def s4_result():
            return inspect(repo, 'S4', base, checkpoint, fixture_result())

        git(repo, 'branch', 'wt/a', base)
        git(repo, 'branch', 'wt/b', base)
        put(repo, 'a.py', 'def value(n): return n + 1\n')
        put(repo, 'b.py', 'def value(n): return n * 2\n')
        put(repo, 'manifest.txt', 'a\nb\n')
        direct = commit(repo, 'Integration writes capabilities and manifest')
        result = s4_result()
        assert not result['accepted'] and result['ownership_attribution_known'], result
        assert result['ownership_violations'] == [{'stream': BRANCH, 'commit': direct, 'path': 'manifest.txt'}]
        git(repo, 'revert', '--no-edit', direct)
        assert any(v.get('commit') == direct for v in s4_result()['ownership_violations'])
        incomplete, known = s4_integration_ownership(repo, base, ref(repo, BRANCH), checkpoint['seed_reflog'],
                                                     integration_log(repo)[:-1], set())
        assert not known and any(v.get('commit') == direct for v in incomplete)
        git(repo, 'reset', '--hard', base)
        assert any(v.get('commit') == direct for v in s4_result()['ownership_violations'])
        checkpoint['seed_reflog'] = integration_log(repo)
        git(repo, 'merge', '--ff-only', direct)
        result = s4_result()
        assert not result['accepted'] and not result['ownership_attribution_known'] and result['ownership_violations'] is None
        git(repo, 'reset', '--hard', base)
        git(repo, 'branch', '-D', 'wt/a', 'wt/b')
        checkpoint['seed_reflog'] = integration_log(repo)

        git(repo, 'checkout', '-qb', 'wt/a', base)
        put(repo, 'a.py', 'def value(n): return n + 1\n')
        first_parent = commit(repo, 'A capability without registration')
        git(repo, 'checkout', '-qb', 'wt/b', base)
        put(repo, 'b.py', 'def value(n): return n * 2\n')
        second_parent = commit(repo, 'B capability without registration')
        git(repo, 'checkout', 'wt/a')
        git(repo, 'merge', '--no-commit', 'wt/b')
        put(repo, 'manifest.txt', 'a\nb\n')
        worker_merge = commit(repo, 'A registers both capabilities in the merge')
        assert git(repo, 'show', '-s', '--format=%P', worker_merge).split() == [first_parent, second_parent]
        assert all('manifest.txt' in changed_paths(repo, p, worker_merge) for p in (first_parent, second_parent))
        git(repo, 'checkout', '-qb', 'wt/manifest', first_parent)
        git(repo, 'merge', '--ff-only', '-m', 'Unused message', 'wt/a')
        assert '\tmerge wt/a: Fast-forward (' in worker_logs(repo)['manifest'][-1]
        violations, known, attributed = s4_ownership(repo, base, head_map(repo, 'S4'), seed, worker_logs(repo))
        assert known and not violations and worker_merge in attributed
        git(repo, 'checkout', BRANCH)
        git(repo, 'merge', '--ff-only', first_parent)
        git(repo, 'merge', '--ff-only', '-m', 'Unused message', 'wt/a')
        log = integration_log(repo)
        assert '\tmerge wt/a: Fast-forward (' in log[-1]
        result = s4_result()
        assert result['accepted'] and result['ownership_attribution_known'] and result['ownership_violations'] == [], result
        assert s4_integration_ownership(repo, base, worker_merge, checkpoint['seed_reflog'], log, set()) == ([], False)
        git(repo, 'reset', '--hard', base)
        checkpoint['seed_reflog'] = integration_log(repo)

        git(repo, 'checkout', '-qb', 'outside-worker', first_parent)
        git(repo, 'merge', '--no-commit', 'wt/b')
        put(repo, 'manifest.txt', 'b\na\n')
        external_merge = commit(repo, 'External merge registers both capabilities')
        assert git(repo, 'show', '-s', '--format=%P', external_merge).split() == [first_parent, second_parent]
        git(repo, 'checkout', 'wt/a')
        git(repo, 'reset', '--hard', first_parent)
        git(repo, 'merge', '--ff-only', 'outside-worker')
        assert worker_logs(repo)['a'][-1].endswith('\tmerge outside-worker: Fast-forward')
        git(repo, 'checkout', BRANCH)
        git(repo, 'merge', '--ff-only', first_parent)
        git(repo, 'merge', '--ff-only', 'wt/a')
        result = s4_result()
        assert not result['accepted'] and not result['ownership_attribution_known'] and result['ownership_violations'] is None, result
        assert external_merge not in s4_ownership(repo, base, head_map(repo, 'S4'), seed, worker_logs(repo))[2]
        git(repo, 'reset', '--hard', base)
        git(repo, 'branch', '-D', 'wt/a', 'wt/b', 'wt/manifest')
        checkpoint['seed_reflog'] = integration_log(repo)

        git(repo, 'checkout', '-qb', 'wt/a', base)
        put(repo, 'a.py', 'def value(n): return n + 1\n')
        put(repo, 'manifest.txt', 'a\nb\n')
        a_head = commit(repo, 'A registers both capabilities')
        git(repo, 'checkout', '-qb', 'wt/b', base)
        put(repo, 'b.py', 'def value(n): return n * 2\n')
        b_head = commit(repo, 'B capability')
        def s4(logs=None):
            return s4_ownership(repo, base, head_map(repo, 'S4'), seed, worker_logs(repo) if logs is None else logs)[:2]

        assert s4() == ([], True)
        git(repo, 'checkout', BRANCH)
        for first, second in (('a', 'b'), ('b', 'a')):
            git(repo, 'merge', '--ff-only', 'wt/' + first)
            git(repo, 'merge', '--no-edit', 'wt/' + second)
            result = s4_result()
            assert result['accepted'] and result['ownership_attribution_known'] and result['ownership_violations'] == []
            unknown = inspect(repo, 'S4', base, {'seed_worker_reflogs': seed}, fixture_result())
            assert not unknown['accepted'] and not unknown['ownership_attribution_known'] and unknown['ownership_violations'] is None
            git(repo, 'reset', '--hard', base)

        git(repo, 'merge', '--ff-only', 'wt/b')
        git(repo, 'merge', '--no-commit', 'wt/a')
        put(repo, 'manifest.txt', 'b\na\n')
        resolution = commit(repo, 'Integration modifies imported manifest')
        result = s4_result()
        assert not result['accepted'] and result['ownership_attribution_known']
        assert result['ownership_violations'] == [{'stream': BRANCH, 'commit': resolution, 'path': 'manifest.txt'}]
        git(repo, 'reset', '--hard', base)
        checkpoint['seed_reflog'] = integration_log(repo)
        git(repo, 'merge', '--ff-only', 'wt/b')
        git(repo, 'cherry-pick', 'wt/a')
        result = s4_result()
        assert not result['accepted'] and not result['ownership_attribution_known'] and result['ownership_violations'] is None
        git(repo, 'reset', '--hard', base)
        checkpoint['seed_reflog'] = integration_log(repo)
        git(repo, 'checkout', 'wt/b')
        git(repo, 'merge', '--no-edit', 'wt/a')
        assert s4() == ([], True)  # A's out-of-scope path for B is a pure import, not B's write.
        git(repo, 'reset', '--hard', b_head)
        git(repo, 'merge', '--no-commit', 'wt/a')
        put(repo, 'merge-extra.txt', 'only in the merge\n')
        merge_edit = commit(repo, 'Merge with an extra write')
        violations, known = s4()
        assert known and len(violations) == 1 and violations[0]['commit'] == merge_edit
        assert 'merge-extra.txt' in violations[0]['check'] and 'a.py' not in violations[0]['check']
        git(repo, 'reset', '--hard', b_head)
        put(repo, 'manifest.txt', 'b\n')
        put(repo, 'not-owned.txt', 'transient B write\n')
        bad = commit(repo, 'B writes shared and out-of-scope paths')
        git(repo, 'reset', '--hard', b_head)
        git(repo, 'checkout', BRANCH)
        git(repo, 'merge', '--ff-only', 'wt/a')
        git(repo, 'merge', '--no-edit', 'wt/b')
        result = s4_result()
        assert not result['accepted'] and result['ownership_attribution_known']
        violations = result['ownership_violations']
        assert {'streams': ['a', 'b'], 'path': 'manifest.txt'} in violations
        assert any(v.get('commit') == bad and 'not-owned.txt' in v['check'] for v in violations)
        logs = worker_logs(repo)
        assert not s4({'a': logs['a']})[1]
        assert not s4({**logs, 'b': logs['b'][1:]})[1]
        assert not s4({**logs, 'b': logs['b'][:-1]})[1]
        unowned = git(repo, 'commit-tree', git(repo, 'rev-parse', 'HEAD^{tree}'), '-p', b_head, '-m', 'Opaque update')
        git(repo, 'update-ref', 'refs/heads/wt/b', unowned)
        assert not s4()[1]
        git(repo, 'update-ref', 'refs/heads/wt/b', b_head)
        detached = Path(tmp) / 'Q0'
        git(repo, 'worktree', 'add', '--detach', str(detached), base)
        sources = {'Q0': detached, 'Q1': repo}
        q1 = source_head(repo)
        assert source_revisions(sources, q1, baseline=base) == {'Q0': base, 'Q1': q1}

        def reject_source(expected, message):
            try:
                source_revisions(sources, expected, baseline=base)
            except ValueError as exc:
                assert message in str(exc), str(exc)
            else:
                raise AssertionError(f'invalid source accepted: {expected}')

        reject_source(None, 'full lowercase')
        reject_source(q1[:12], 'full lowercase')
        reject_source(a_head, 'Q1 checkout must be')
        git(repo, 'checkout', '--detach', base)
        reject_source(base, 'strict descendant')
        unrelated = git(repo, 'commit-tree', git(repo, 'rev-parse', 'HEAD^{tree}'), '-m', 'Unrelated root')
        git(repo, 'checkout', '--detach', unrelated)
        reject_source(unrelated, 'strict descendant')
        git(repo, 'checkout', BRANCH)
        put(repo, 'untracked', 'dirty checkout')
        reject_source(q1, 'not a clean Git source checkout')
        (repo / 'untracked').unlink()
        # Diverged Q0 (e.g. sibling v1 vs v2): rejected by default, allowed with --allow-diverged-q0.
        sibling = Path(tmp) / 'Q0-sibling'
        git(repo, 'worktree', 'add', '-b', 'q0-sibling', str(sibling), base)
        put(sibling, 'sibling.txt', 'v1 sibling change\n')
        q0_sibling = commit(sibling, 'Sibling Q0 commit')
        diverged_sources = {'Q0': sibling, 'Q1': repo}
        try:
            source_revisions(diverged_sources, q1, baseline=base)
        except ValueError as exc:
            assert 'Q0 checkout must be' in str(exc), str(exc)
        else:
            raise AssertionError('diverged Q0 accepted without --allow-diverged-q0')
        try:
            source_revisions(diverged_sources, q1, baseline=q0_sibling)
        except ValueError as exc:
            assert 'strict descendant' in str(exc), str(exc)
        else:
            raise AssertionError('non-descendant Q1 accepted without --allow-diverged-q0')
        assert source_revisions(diverged_sources, q1, baseline=base, allow_diverged_q0=True) == {
            'Q0': q0_sibling, 'Q1': q1, 'merge_base': base,
        }
        try:
            source_revisions({'Q0': repo, 'Q1': repo}, q1, baseline=base, allow_diverged_q0=True)
        except ValueError as exc:
            assert 'must differ from Q0' in str(exc), str(exc)
        else:
            raise AssertionError('identical Q0/Q1 accepted with --allow-diverged-q0')
        git(sibling, 'checkout', '--detach', unrelated)
        try:
            source_revisions(diverged_sources, q1, baseline=base, allow_diverged_q0=True)
        except ValueError as exc:
            assert 'merge base' in str(exc), str(exc)
        else:
            raise AssertionError('unrelated Q0/Q1 accepted with --allow-diverged-q0')
        repo = Path(tmp) / 'S3'
        base = ref(repo, 'main')
        api = Path(tmp) / 'api'
        consumer = Path(tmp) / 'consumer'
        git(repo, 'worktree', 'add', '-b', 'wt/api', str(api), base)
        git(repo, 'worktree', 'add', '-b', 'wt/consumer', str(consumer), base)
        put(api, 'shared/types/error.py', 'KEY = "errorCode"\n')
        api_head = commit(api, 'Change error field')
        put(consumer, 'b.py', 'def render(error):\n    return str(error["errorCode"])\n')
        consumer_head = commit(consumer, 'Read errorCode')
        prefix = 'STREAM consumer; VERDICT PASS; REF wt/consumer@'
        fields = f'; BASE {base}; VERIFIED_AGAINST '
        unbound = prefix + consumer_head + fields + 'none'
        wrong_head = prefix + base + fields + f'api=wt/api@{api_head}'
        exact = prefix + consumer_head + fields + f'api=wt/api@{api_head}'
        assert not matched(repo, snapshot(repo, 'S3', unbound + '\n' + wrong_head), base, 'consumer', inputs={'api': api_head})
        assert matched(repo, snapshot(repo, 'S3', exact), base, 'consumer', inputs={'api': api_head})
        conflicting = exact + '\n' + exact.replace('VERDICT PASS', 'VERDICT FAIL')
        result = inspect(repo, 'S3', base, {}, fixture_result(conflicting))
        assert 'consumer' not in result['structured_pass_streams']
        result = inspect(repo, 'S3', base, {}, fixture_result(unbound))
        assert result['stale_evidence'] is None and 'consumer' not in result['structured_pass_streams']
        assert result['reported_verdict_bindings']['final'][0]['unsupported_fields'] == ['api']
        unresolved = prefix + consumer_head + fields + 'api=wt/api@0000000'
        result = inspect(repo, 'S3', base, {}, fixture_result(unresolved))
        assert result['stale_evidence'] is None and result['reported_verdict_bindings']['final'][0]['unsupported_fields'] == ['api']
        stale_input = prefix + consumer_head + fields + f'api=wt/api@{base}'
        result = inspect(repo, 'S3', base, {}, fixture_result(stale_input))
        assert result['stale_evidence'] == 1 and result['reported_verdict_bindings']['final'][0]['stale_fields'] == ['api']
        result = inspect(repo, 'S3', base, {}, fixture_result(exact))
        assert result['stale_evidence'] == 0 and result['structured_pass_streams'] == ['consumer']
        assert result['reported_verdict_bindings']['final'][0]['provenance_known'] is None
        result = inspect(repo, 'S3', base, {}, fixture_result(exact + '\n' + unbound))
        assert result['stale_evidence'] is None
        legacy = fixture_result(f'LEGACY_STREAM consumer; VERDICT PASS; HEAD {base}')
        assert inspect(repo, 'S3', base, {}, legacy)['stale_evidence'] == 1
        repo = Path(tmp) / 'S5b'
        base = ref(repo, 'main')
        seed = integration_log(repo)
        git(repo, 'checkout', '-qb', 'wt/api', base)
        put(repo, 'a.py', 'def encode(n):\n    return str(n)\n')
        api_head = commit(repo, 'Decimal format')
        git(repo, 'checkout', '-qb', 'wt/consumer', base)
        put(repo, 'b.py', 'def decode(s):\n    if not s.startswith("#"):\n        raise ValueError(s)\n    return int(s[1:])\n')
        consumer_head = commit(repo, 'Prefixed format')
        assert initial_join_failure(repo, base, seed, snapshot(repo, 'S5b', '')) is None
        git(repo, 'checkout', BRANCH)
        git(repo, 'merge', '--ff-only', api_head)
        git(repo, 'merge', '--no-edit', consumer_head)
        snap = snapshot(repo, 'S5b', '')
        first = initial_join_failure(repo, base, seed, snap)
        assert first['observed'] and first['inputs'] == {'api': api_head, 'consumer': consumer_head}
        assert not first['reported_binding']
        joined = snap['integration']
        claim = (f'JOIN; VERDICT FAIL; INTEGRATION_REF {BRANCH}@{joined}; BASE {base}; '
                 f'INPUT_REFS api={api_head},consumer={consumer_head}')
        assert initial_join_failure(repo, base, seed, snapshot(repo, 'S5b', claim))['reported_binding']
        conflicting = claim + '\n' + claim.replace('VERDICT FAIL', 'VERDICT PASS')
        assert not initial_join_failure(repo, base, seed, snapshot(repo, 'S5b', conflicting))['reported_binding']
    print('PASS: offline acceptance, trace metrics, verdict bindings, scenario gates, pinned sources and paired plans')


def source_head(source):
    if (Path(git(source, 'rev-parse', '--show-toplevel')).resolve() != source
            or git(source, 'status', '--porcelain', '--untracked-files=all')):
        raise ValueError(f'not a clean Git source checkout: {source}')
    return git(source, 'rev-parse', '--verify', 'HEAD')


def merge_base(repo, other_repo, a, b):
    env = os.environ.copy()
    alt_objects = git(other_repo, 'rev-parse', '--path-format=absolute', '--git-path', 'objects')
    existing_alt = env.get('GIT_ALTERNATE_OBJECT_DIRECTORIES')
    env['GIT_ALTERNATE_OBJECT_DIRECTORIES'] = f'{alt_objects}:{existing_alt}' if existing_alt else alt_objects
    p = run(repo, 'git', 'merge-base', a, b, check=False, text=True, env=env)
    return p.stdout.strip() if p.returncode == 0 else None


def source_revisions(sources, expected_q1, baseline=Q0, allow_diverged_q0=False):
    if not expected_q1 or not re.fullmatch(r'[a-f0-9]{40}', expected_q1):
        raise ValueError('--q1-sha must be a full lowercase 40-character commit SHA')
    revisions = {variant: source_head(source) for variant, source in sources.items()}
    if revisions['Q1'] != expected_q1:
        raise ValueError(f'Q1 checkout must be at {expected_q1}, found {revisions["Q1"]}')
    if not allow_diverged_q0:
        if revisions['Q0'] != baseline:
            raise ValueError(f'Q0 checkout must be at {baseline}, found {revisions["Q0"]}')
        if expected_q1 == revisions['Q0'] or not ancestor(sources['Q1'], revisions['Q0'], expected_q1):
            raise ValueError('Q1 must be a strict descendant of Q0')
        return revisions
    if expected_q1 == revisions['Q0']:
        raise ValueError('Q1 must differ from Q0 when --allow-diverged-q0 is set')
    mb = merge_base(sources['Q1'], sources['Q0'], revisions['Q0'], expected_q1)
    if not mb:
        raise ValueError('Q0 and Q1 must share a merge base')
    return {**revisions, 'merge_base': mb}


def same_revision(checkout, expected):
    if not expected or not re.fullmatch(r'[a-f0-9]{40}', expected):
        raise ValueError('--q1-sha must be a full lowercase 40-character commit SHA')
    checkout = Path(checkout).resolve()
    found = source_head(checkout)
    if found != expected:
        raise ValueError(f'checkout must be at {expected}, found {found}')
    return found


def comparison_plan(scenarios, trials, *, same_revision):
    if not isinstance(trials, int) or trials < 1:
        raise ValueError('trials must be positive')
    variants = (('v1', 'v1'), ('v2', 'v2')) if same_revision else (('Q0', None), ('Q1', None))
    plan = []
    for scenario in scenarios:
        for index in range(1, trials + 1):
            ordered = variants[::-1] if same_revision and index % 2 == 0 else variants
            for variant, workflow in ordered:
                plan.append({'scenario': scenario, 'trial': index, 'variant': variant, 'workflow': workflow})
    return plan


def prove_same_revision():
    help_text = run(HERE, sys.executable, str(Path(__file__).resolve()), '--help', text=True).stdout
    assert '--same-revision' in help_text
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / 'source'
        source.mkdir()
        (source / 'install.sh').write_text(
            '#!/bin/sh\n'
            'target=\n'
            'prev=\n'
            'for arg in "$@"; do\n'
            '  if [ "$prev" = "--target" ]; then\n'
            '    target=$arg\n'
            '  fi\n'
            '  prev=$arg\n'
            'done\n'
            'test -n "$target" || exit 2\n'
            "printf '%s\\n' \"$@\" > \"$target/install-argv\"\n")
        plan = comparison_plan(('S1',), 1, same_revision=True)
        assert [(item['variant'], item['workflow']) for item in plan] == [('v1', 'v1'), ('v2', 'v2')]
        recorded = []
        for item in plan:
            target = root / item['workflow']
            target.mkdir()
            command = install_command(source, target, item['workflow'])
            assert command[:2] == ('bash', str(source / 'install.sh'))
            run(target, *command)
            recorded.append((target / 'install-argv').read_text().splitlines())
            assert recorded[-1] == [
                '--harness', 'claude', '--scope', 'project', '--target', str(target),
                '--workflow', item['workflow'], '--no-tui', '--no-web']
        def without(row, flag):
            row = list(row)
            index = row.index(flag)
            del row[index:index + 2]
            return row

        assert recorded[0] != recorded[1]
        assert [row[row.index('--workflow') + 1] for row in recorded] == ['v1', 'v2']
        assert without(without(recorded[0], '--target'), '--workflow') == without(without(recorded[1], '--target'), '--workflow')
        try:
            install_command(source, root, 'v3')
        except ValueError as exc:
            assert 'v1 or v2' in str(exc)
        else:
            raise AssertionError('invalid workflow accepted')
        plain = root / 'plain'
        plain.mkdir()
        historical = install_command(source, plain, None)
        assert historical == (
            'bash', str(source / 'install.sh'), '--harness', 'claude', '--scope', 'project',
            '--target', str(plain), '--no-tui', '--no-web')
        run(plain, *historical)
        assert '--workflow' not in (plain / 'install-argv').read_text().splitlines()
        assert comparison_plan(('S1', 'S2'), 3, same_revision=False) == [
            {'scenario': scenario, 'trial': index, 'variant': variant, 'workflow': None}
            for scenario in ('S1', 'S2') for index in (1, 2, 3) for variant in ('Q0', 'Q1')]

        repo = root / 'checkout'
        repo.mkdir()
        git(repo, 'init', '-q', '-b', 'main')
        git(repo, 'config', 'user.name', 'Quintet fixture')
        git(repo, 'config', 'user.email', 'fixture@example.invalid')
        put(repo, 'a.txt', 'shared\n')
        sha = commit(repo, 'Shared revision')
        assert same_revision(repo, sha) == sha
        out = root / 'benchmark'
        out.mkdir()
        args = argparse.Namespace(scenario=['S1'], trials=3, same_revision=True,
                                  model='fixture-model', budget=1, timeout=60)
        sources = {'v1': repo, 'v2': repo}
        revisions = {'v1': sha, 'v2': sha}
        observed = []

        def fixture_trial(source, trial_out, config, scenario, *, legacy, workflow):
            observed.append((trial_out.name, workflow, legacy))
            assert (source, source_head(source), scenario) == (repo, sha, 'S1')
            assert (config.model, config.budget, config.timeout) == ('fixture-model', 1, 60)
            if trial_out.name == 'S1-2-v2':
                raise RuntimeError('fixture blocked')
            return {'accepted': True}

        stdout = StringIO()
        manifest = comparison_manifest(args, sources, revisions)
        with patch(f'{__name__}.trial', side_effect=fixture_trial), redirect_stdout(stdout):
            run_comparison(args, sources, revisions, out, 'fixture-claude', manifest)
        assert json.loads((out / 'plan.json').read_text()) == {**manifest, 'claude': 'fixture-claude'}
        plan_args = (sys.executable, str(Path(__file__).resolve()), '--plan', '--same-revision', '--q1', str(repo),
                     '--q1-sha', sha, '--model', 'fixture-model', '--budget', '1', '--timeout', '60',
                     '--scenario', 'S1', '--trials', '3')
        assert json.loads(run(HERE, *plan_args, text=True).stdout) == manifest
        assert manifest['max_invocations'] == 6 and manifest['max_configured_budget_usd'] == 6
        assert run(HERE, *plan_args, '--live', check=False).returncode == 2
        assert run(HERE, *plan_args, '--budget', 'nan', check=False).returncode == 2
        expected = [(1, 'v1', 1), (1, 'v2', 2), (2, 'v2', 1), (2, 'v1', 2),
                    (3, 'v1', 1), (3, 'v2', 2)]
        assert observed == [(f'S1-{index}-{variant}', variant, variant == 'v1')
                            for index, variant, _ in expected]
        results = [json.loads(line) for line in stdout.getvalue().splitlines()]
        assert [(row['trial'], row['variant'], row['pair_position']) for row in results] == expected
        for row in results:
            result_path = out / f"S1-{row['trial']}-{row['variant']}" / 'result.json'
            assert json.loads(result_path.read_text()) == row
            assert row['workflow'] == row['variant']
            assert row['source_revisions'] == revisions
            assert row['model'] == args.model
        assert results[2]['accepted'] is False and results[2]['blocked'] == 'fixture blocked'
        assert all(row['accepted'] for row in results[:2] + results[3:])
        put(repo, 'dirty.txt', 'dirty\n')
        try:
            same_revision(repo, sha)
        except ValueError as exc:
            assert 'not a clean Git source checkout' in str(exc)
        else:
            raise AssertionError('dirty same-revision checkout accepted')
        (repo / 'dirty.txt').unlink()
        assert same_revision(repo, sha) == sha
        put(repo, 'a.txt', 'changed\n')
        other = commit(repo, 'Later revision')
        try:
            same_revision(repo, sha)
        except ValueError as exc:
            assert f'checkout must be at {sha}' in str(exc)
        else:
            raise AssertionError('stale same-revision SHA accepted')
        assert same_revision(repo, other) == other
        for bad in (None, '', sha[:12], sha.upper()):
            try:
                same_revision(repo, bad)
            except ValueError as exc:
                assert 'full lowercase' in str(exc), str(exc)
            else:
                raise AssertionError(f'short or empty SHA accepted: {bad!r}')


def comparison_manifest(args, sources, revisions):
    plan = comparison_plan(args.scenario or SCENARIOS, args.trials, same_revision=args.same_revision)
    for position, item in enumerate(plan):
        item['pair_position'] = position % 2 + 1
        item['max_invocations'] = MAX_INVOCATIONS.get(item['scenario'], 1)
    invocations = sum(item['max_invocations'] for item in plan)
    return {'comparison': 'same-revision' if args.same_revision else 'historical',
            'runner_sha256': sha256(Path(__file__).read_bytes()).hexdigest(),
            'sources': {key: str(path) for key, path in sources.items()}, 'source_revisions': revisions,
            'model': args.model, 'trials_per_scenario_and_variant': args.trials,
            'budget_usd_per_invocation': args.budget, 'timeout_seconds_per_invocation': args.timeout,
            'max_invocations': invocations, 'max_configured_budget_usd': args.budget * invocations,
            'trials': plan}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--self-test', action='store_true')
    mode.add_argument('--plan', action='store_true', help='validate local inputs and print the trial plan without Claude')
    mode.add_argument('--live', action='store_true', help='explicit opt-in to authenticated, potentially billed calls')
    for name in ('q0', 'q1', 'out'):
        parser.add_argument('--' + name, type=Path)
    parser.add_argument('--q1-sha', help='exact full commit SHA of the --q1 checkout for --plan and --live')
    parser.add_argument('--allow-diverged-q0', action='store_true',
                        help='allow Q0 to be a diverged sibling branch checkout (such as v1) and record merge_base')
    parser.add_argument('--same-revision', action='store_true',
                        help='compare workflow v1 and v2 from one clean --q1 checkout at --q1-sha')
    parser.add_argument('--model', help='same pinned model for both variants')
    parser.add_argument('--budget', type=float, help='USD per invocation (up to three for S5, two for S3 and S5b)')
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--scenario', action='append', choices=SCENARIOS, help='can repeat; defaults to all')
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    if not args.q1 or not args.model or not args.budget or not math.isfinite(args.budget) or args.budget <= 0:
        parser.error('--plan and --live require --q1, --q1-sha, --model and a finite positive --budget')
    if args.live and not args.out:
        parser.error('--live requires --out')
    if args.trials < 1 or args.timeout < 1:
        parser.error('--trials and --timeout must be positive')
    if args.scenario and len(args.scenario) != len(set(args.scenario)):
        parser.error('--scenario values must be distinct')
    if args.same_revision:
        if args.q0 or args.allow_diverged_q0:
            parser.error('--same-revision uses one --q1 checkout. Omit --q0 and --allow-diverged-q0')
        source = args.q1.resolve()
        sources = {'v1': source, 'v2': source}
        try:
            revision = same_revision(source, args.q1_sha)
        except (ValueError, OSError, subprocess.CalledProcessError) as exc:
            parser.error(str(exc))
        revisions = {'v1': revision, 'v2': revision}
        outside = 'the source checkout'
    else:
        if not args.q0:
            parser.error('historical trials require --q0. Use --same-revision for a single pinned source')
        sources = {'Q0': args.q0.resolve(), 'Q1': args.q1.resolve()}
        try:
            revisions = source_revisions(sources, args.q1_sha, allow_diverged_q0=args.allow_diverged_q0)
        except (ValueError, OSError, subprocess.CalledProcessError) as exc:
            parser.error(str(exc))
        outside = 'both source checkouts'
    manifest = comparison_manifest(args, sources, revisions)
    if not math.isfinite(manifest['max_configured_budget_usd']):
        parser.error('configured total budget must be finite')
    if args.plan:
        print(json.dumps(manifest, indent=2))
        return
    root = args.out.resolve()
    if any(root.is_relative_to(source) for source in (HERE, *sources.values())):
        parser.error(f'--out must be outside the runner and {outside}')
    version = run(HERE, 'claude', '--version', text=True).stdout.strip()
    root.mkdir(parents=True, exist_ok=False)
    run_comparison(args, sources, revisions, root, version, manifest)


def run_comparison(args, sources, revisions, root, version, manifest):
    put(root, 'plan.json', json.dumps({**manifest, 'claude': version}, indent=2) + '\n')
    for item in manifest['trials']:
        scenario, index, variant, workflow = item['scenario'], item['trial'], item['variant'], item['workflow']
        source = sources[variant]
        out = root / f'{scenario}-{index}-{variant}'
        out.mkdir()
        try:
            if source_head(source) != revisions[variant]:
                raise ValueError(f'{variant} source revision changed')
            # v1 may report a legacy HEAD line. v2 still requires bound verdicts.
            result = trial(source, out, args, scenario, legacy=variant == 'Q0' or workflow == 'v1', workflow=workflow)
        except (RuntimeError, subprocess.SubprocessError, ValueError, OSError) as exc:
            result = blocked_result(out, exc, scenario)
        result.update(item, claude=version, model=args.model, source_revisions=revisions,
                      budget_usd_per_invocation=args.budget, timeout_seconds_per_invocation=args.timeout)
        put(out, 'result.json', json.dumps(result, indent=2) + '\n')
        print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
