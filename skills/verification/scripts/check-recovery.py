#!/usr/bin/env python3
"""Record and gate v2 recovery attempts in a task's SQLite ledger."""

import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

DEFAULT_LIMIT = 8
DEFAULT_CHECK_SET = "default"
STAGNATION_LIMIT = 2


class RecoveryError(Exception):
    pass


def nonempty(value):
    value = value.strip()
    if not value:
        raise argparse.ArgumentTypeError("expected nonempty text")
    return value


def positive(value):
    number = int(value)
    if not 0 < number < 2**63:
        raise argparse.ArgumentTypeError("expected a positive SQLite integer")
    return number


def parser():
    cli = argparse.ArgumentParser(
        description=__doc__,
        epilog="Requires Python 3.7 or newer with the standard-library sqlite3 module.",
        allow_abbrev=False,
    )
    cli.add_argument("--ledger", required=True, type=Path, help="durable path outside worker checkouts")
    commands = cli.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="create a ledger and pin its per-scope retry limit")
    init.add_argument("--limit", type=positive, default=DEFAULT_LIMIT, help="retry limit (default: %(default)s)")
    status = commands.add_parser("status", help="read the ledger and attempt history")
    status.add_argument("scope", nargs="?", type=nonempty)

    descriptions = {
        "baseline": "record initial failures for a stable scope",
        "begin": "reserve the next numbered retry before starting work",
        "finish": "record the outcome of the pending retry",
        "reopen": "record a new observed failure after a scope passed",
        "strategy": "record Nora's evidence and a changed tactic after stagnation",
        "assumption": "record evidence that requires an architecture or dependency replan",
        "replan": "record the changed architecture or dependency plan",
        "block": "pause for an external blocker requiring user action",
        "unblock": "record evidence of user intervention and lift an external pause",
    }
    for name, description in descriptions.items():
        command = commands.add_parser(name, help=description, description=description, allow_abbrev=False)
        command.add_argument("scope", type=nonempty, help="original stream ID or the reserved integration scope")
        command.add_argument("--evidence", required=True, type=nonempty, help="observation or durable evidence reference")
        if name in ("begin", "finish"):
            command.add_argument("--attempt", type=positive, required=True, help="retry number shown by status")
        if name == "begin":
            command.add_argument("--kind", choices=("edit", "recheck"), required=True)
        if name == "unblock":
            command.add_argument("--block", dest="block_sequence", type=positive, required=True,
                                 help="block_sequence shown by status for the active blocker")
        if name in ("baseline", "finish", "reopen"):
            command.add_argument("--check-set", type=nonempty,
                                 help=f"stable check set ID for comparing counts (default: {DEFAULT_CHECK_SET})")
            command.add_argument(
                "--failure", type=nonempty, action="append", default=[], help="stable failure ID, repeatable"
            )
            command.add_argument(
                "--assumption", action="store_true", help="evidence invalidates an architecture or dependency assumption"
            )
        if name in ("finish", "reopen"):
            command.add_argument(
                "--incomparable", action="store_true", help="exclude this failure count from comparisons"
            )
        if name == "finish":
            command.add_argument("--result", choices=("pass", "fail", "abandoned"), required=True)
            command.add_argument(
                "--progress-key", type=nonempty, help="stable ID for a clearer cause or measured advance"
            )
            command.add_argument(
                "--progress-evidence", type=nonempty, help="evidence of the change, required with --progress-key"
            )
    return cli


def failure_fields(args, comparable):
    if not args.failure:
        raise RecoveryError("an observed failure requires at least one --failure")
    failures = sorted(set(args.failure))
    return {
        "failures": failures,
        "fingerprint": hashlib.sha256(json.dumps(failures).encode()).hexdigest(),
        "check_set": args.check_set or DEFAULT_CHECK_SET,
        "comparable": comparable,
        "assumption": args.assumption,
    }


def current_episode(history):
    for index in range(len(history) - 1, -1, -1):
        if history[index].get("result") == "pass":
            return history[index + 1:]
    return history


def recurred_after_replan(episode, fingerprint):
    return (any(event["action"] == "replan" for event in episode)
            and any(event.get("fingerprint") == fingerprint for event in episode))


def view(history, limit):
    last = history[-1]
    used = sum(event["action"] == "begin" for event in history)
    remaining = limit - used
    return {
        "state": last["state"],
        "reason": last["reason"],
        "used": used,
        "remaining": remaining,
        "next_attempt": used + 1 if last["state"] == "ready" and remaining > 0 else None,
        "pending_attempt": last.get("attempt") if last["state"] == "in_flight" else None,
        "block_sequence": last["sequence"] if last["action"] == "block" else None,
        "replan_pending": last["state"] == "replan" or last.get("replan_pending", False),
        "stagnation": last["stagnation"],
        "history": history,
    }


def result_fields(args, scope):
    last = scope["history"][-1]
    if args.attempt != scope["pending_attempt"]:
        raise RecoveryError("finish requires the current pending attempt number")
    if bool(args.progress_key) != bool(args.progress_evidence):
        raise RecoveryError("supply --progress-key and --progress-evidence together")
    if args.result != "fail" and (args.failure or args.progress_key or args.incomparable or args.check_set):
        raise RecoveryError("failure IDs, progress evidence, --check-set and --incomparable require --result fail")
    if args.result == "pass" and args.assumption:
        raise RecoveryError("--assumption requires a failed or abandoned attempt")

    fields = {"attempt": args.attempt, "result": args.result, "assumption": args.assumption}
    if args.result == "pass":
        return dict(fields, state="complete", reason="passed", stagnation=0)

    progress = []
    recurrence = False
    history = scope["history"]
    if args.result == "fail":
        fields.update(failure_fields(args, comparable=not args.incomparable))
        episode = current_episode(history)
        comparable_counts = (
            len(event["failures"]) for event in episode
            if event.get("comparable") and event.get("check_set", DEFAULT_CHECK_SET) == fields["check_set"]
        )
        best = min(comparable_counts, default=None)
        if not args.incomparable and best is not None and len(fields["failures"]) < best:
            progress.append("fewer_failures")
        if args.progress_key:
            evidence = " ".join(args.progress_evidence.split())
            fields.update(progress_key=args.progress_key, progress_evidence=args.progress_evidence)
            already_recorded = any(
                event.get("progress_key") == args.progress_key
                or " ".join(event.get("progress_evidence", "").split()) == evidence
                for event in history
            )
            if not already_recorded:
                progress.append("new_evidence")
        recurrence = recurred_after_replan(episode, fields["fingerprint"])

    stagnation = 0 if progress else last["stagnation"] + 1
    state, reason = "ready", "progress" if progress else "no_progress"
    if recurrence:
        state, reason = "stopped", "failure_recurred_after_replan"
    elif scope["remaining"] == 0:
        state, reason = "stopped", "limit_reached"
    elif stagnation >= STAGNATION_LIMIT:
        state, reason = "change_strategy", "stagnation"
    elif args.assumption:
        state, reason = "replan", "assumption_invalidated"
    return dict(fields, state=state, reason=reason, stagnation=stagnation, progress=progress,
                replan_pending=state == "change_strategy" and args.assumption)


def record(args, scope):
    action = args.command
    if action == "baseline":
        if scope is not None:
            raise RecoveryError("scope already baselined; reuse its original ID and history")
        state, reason = ("replan", "assumption_invalidated") if args.assumption else ("ready", "baseline")
        return dict(failure_fields(args, comparable=True), state=state, reason=reason, stagnation=0)
    if scope is None:
        raise RecoveryError("baseline this scope first")

    state = scope["state"]
    stagnation = scope["stagnation"]
    if action == "finish":
        return result_fields(args, scope)
    if action == "reopen" and state == "complete":
        fields = failure_fields(args, comparable=not args.incomparable)
        state, reason = "ready", "new_failure"
        if scope["remaining"] == 0:
            state, reason = "stopped", "limit_reached"
        elif args.assumption:
            state, reason = "replan", "assumption_invalidated"
        return dict(fields, state=state, reason=reason, stagnation=0)
    if action == "begin" and state == "ready":
        if args.attempt != scope["next_attempt"]:
            raise RecoveryError("begin requires the next attempt number")
        return dict(state="in_flight", reason="reserved", stagnation=stagnation, attempt=args.attempt, kind=args.kind)
    if action == "strategy" and state == "change_strategy":
        if scope["replan_pending"]:
            return dict(state="replan", reason="assumption_invalidated", stagnation=0)
        return dict(state="ready", reason="strategy_changed", stagnation=0)
    if action == "assumption" and state == "change_strategy":
        return dict(state=state, reason=scope["reason"], stagnation=stagnation, replan_pending=True)
    if action == "assumption" and state == "ready":
        return dict(state="replan", reason="assumption_invalidated", stagnation=stagnation)
    if action == "replan" and state == "replan":
        return dict(state="ready", reason="replanned", stagnation=0)
    if action == "block" and state not in ("complete", "stopped"):
        fields = {"attempt": scope["pending_attempt"]} if state == "in_flight" else {}
        return dict(fields, state="stopped", reason="external_blocker", stagnation=stagnation,
                    replan_pending=scope["replan_pending"])
    if action == "unblock" and scope["block_sequence"] is not None:
        if args.block_sequence != scope["block_sequence"]:
            raise RecoveryError("unblock requires the active block_sequence shown by status")
        previous = scope["history"][-2]
        fields = {"attempt": previous["attempt"]} if previous["state"] == "in_flight" else {}
        return dict(fields, state=previous["state"], reason=previous["reason"], stagnation=stagnation,
                    replan_pending=scope["replan_pending"], block_sequence=args.block_sequence)
    raise RecoveryError(f"{action} is unavailable while scope is {state} ({scope['reason']})")


def run(db, args):
    if args.command == "init":
        if db.execute("SELECT 1 FROM sqlite_master LIMIT 1").fetchone():
            raise RecoveryError("ledger already initialized or path contains another database")
        db.execute("CREATE TABLE settings (attempt_limit INTEGER NOT NULL)")
        db.execute("INSERT INTO settings VALUES (?)", (args.limit,))
        db.execute("""CREATE TABLE events (
            sequence INTEGER PRIMARY KEY, scope TEXT NOT NULL,
            recorded_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, data TEXT NOT NULL
        )""")
        return {"limit": args.limit, "stagnation_limit": STAGNATION_LIMIT, "scopes": {}}

    setting = db.execute("SELECT attempt_limit FROM settings").fetchone()
    if setting is None:
        raise RecoveryError("ledger has no pinned retry limit")
    limit = setting[0]
    sql = "SELECT sequence, scope, recorded_at, data FROM events"
    if args.scope is None:
        rows = db.execute(sql + " ORDER BY sequence")
    else:
        rows = db.execute(sql + " WHERE scope = ? ORDER BY sequence", (args.scope,))
    histories = {}
    for sequence, scope, recorded_at, data in rows:
        event = dict(json.loads(data), sequence=sequence, recorded_at=recorded_at)
        histories.setdefault(scope, []).append(event)
    scopes = {scope: view(history, limit) for scope, history in histories.items()}

    if args.command == "status":
        if args.scope is not None and args.scope not in scopes:
            raise RecoveryError("unknown scope; check status without a scope for the original IDs")
    else:
        event = record(args, scopes.get(args.scope))
        event.update(action=args.command, evidence=args.evidence)
        cursor = db.execute("INSERT INTO events (scope, data) VALUES (?, ?)", (args.scope, json.dumps(event)))
        sequence = cursor.lastrowid
        (recorded_at,) = db.execute("SELECT recorded_at FROM events WHERE sequence = ?", (sequence,)).fetchone()
        event.update(sequence=sequence, recorded_at=recorded_at)
        history = histories.get(args.scope, []) + [event]
        scopes[args.scope] = view(history, limit)
    return {"limit": limit, "stagnation_limit": STAGNATION_LIMIT, "scopes": scopes}


def main():
    args = parser().parse_args()
    mode = {"init": "rwc", "status": "ro"}.get(args.command, "rw")
    try:
        with closing(sqlite3.connect(f"{args.ledger.resolve().as_uri()}?mode={mode}", uri=True)) as db, db:
            db.execute("BEGIN" if mode == "ro" else "BEGIN IMMEDIATE")
            output = run(db, args)
    except RecoveryError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    except (OSError, RuntimeError, sqlite3.Error, ValueError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 2
    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
