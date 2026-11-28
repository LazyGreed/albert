#!/usr/bin/env python3
"""Exercise the recovery checker through separate offline CLI invocations."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

CHECKER = Path(__file__).resolve().parents[1] / "skills/verification/scripts/check-recovery.py"


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.ledger = Path(directory.name) / "task recovery #1.sqlite3"
        self.cli = [str(CHECKER), "--ledger", str(self.ledger)]

    def call(self, *args, code=0):
        result = subprocess.run([*self.cli, *args], capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result.stderr if code else json.loads(result.stdout)

    def scope(self, action, *options, name="api", code=0):
        output = self.call(action, name, *options, code=code)
        return output if code else output["scopes"][name]

    def baseline(self, *failures, name="api", extra=()):
        return self.scope("baseline", *self.failure_args(failures), *extra, "--evidence", "Initial failed checks", name=name)

    @staticmethod
    def failure_args(failures):
        return [option for failure in failures for option in ("--failure", failure)]

    def begin(self, number, *, kind="recheck", name="api", code=0):
        return self.scope("begin", "--attempt", str(number), "--kind", kind,
                          "--evidence", "Check the known failure in the native session", name=name, code=code)

    def finish(self, number, *failures, result="fail", evidence="Observed failed checks", name="api", extra=(), code=0):
        return self.scope("finish", "--attempt", str(number), "--result", result,
                          *self.failure_args(failures), "--evidence", evidence, *extra, name=name, code=code)

    def test_default_limit_and_final_pass(self):
        self.call("status", code=2)
        self.assertFalse(self.ledger.exists())
        self.call("init", "--limit", "0", code=2)
        self.assertEqual(self.call("init"), {"limit": 8, "stagnation_limit": 2, "scopes": {}})
        failures = [f"test:{i}" for i in range(8)]
        self.baseline(*failures)
        for number in range(1, 8):
            self.begin(number)
            state = self.finish(number, *failures[number:])
            self.assertEqual(state["next_attempt"], number + 1)
            self.assertEqual(state["history"][-1]["progress"], ["fewer_failures"])
        self.begin(8)
        state = self.finish(8, result="pass", evidence="Vera PASS at api@def")
        self.assertEqual((state["state"], state["used"], state["remaining"]), ("complete", 8, 0))
        self.begin(9, code=1)
        state = self.scope("reopen", "--failure", "test:new", "--evidence", "Tests failed after target moved")
        self.assertEqual((state["state"], state["reason"], state["used"]), ("stopped", "limit_reached", 8))
        self.begin(9, code=1)
        self.assertEqual(self.scope("status"), state)

    def test_pinned_override_and_shared_integration_scope(self):
        self.call("init", "--limit", "2")
        self.baseline("api:contract")
        self.baseline("join:contract", name="integration")
        self.begin(1, kind="edit", name="integration")
        self.finish(1, result="pass", name="integration", evidence="Combined check passed at join@abc")
        # A new integration branch and an owner rename both retain the original scope.
        state = self.scope("reopen", "--failure", "join:contract", "--evidence", "Combined failure at rebuilt-join@def",
                           name="integration")
        self.assertEqual((state["next_attempt"], state["used"], state["remaining"]), (2, 1, 1))
        self.scope("baseline", "--failure", "api:contract", "--evidence", "api now called billing", code=1)
        self.begin(1, kind="edit")
        self.finish(1, result="pass", evidence="Vera PASS for the routed owner fix in billing@def")
        self.begin(2, name="integration")
        state = self.finish(2, "join:contract", name="integration")
        self.assertEqual((state["state"], state["reason"]), ("stopped", "limit_reached"))
        self.begin(3, name="integration", code=1)
        self.scope("unblock", "--block", "1", "--evidence", "No external pause was recorded",
                   name="integration", code=1)
        self.call("init", "--limit", "9", code=1)
        snapshot = self.call("status")
        self.assertEqual(snapshot["limit"], 2)
        self.assertEqual(snapshot["scopes"]["api"]["used"], 1)
        self.assertEqual(snapshot["scopes"]["integration"]["used"], 2)
        state = self.scope("reopen", "--failure", "api:contract", "--evidence", "Upstream changed after Vera PASS")
        self.assertEqual((state["state"], state["next_attempt"]), ("ready", 2))
        self.assertEqual([event["action"] for event in state["history"]], ["baseline", "begin", "finish", "reopen"])

    def test_stagnation_normalizes_failure_ids(self):
        self.call("init")
        self.begin(1, code=1)
        baseline = self.baseline("test:z", "test:a", "test:a")
        self.begin(1)
        state = self.finish(1, "test:a", "test:z", evidence="Fresh ref branch@222, same failing checks")
        self.assertEqual(state["stagnation"], 1)
        self.assertEqual(state["history"][-1]["fingerprint"], baseline["history"][0]["fingerprint"])
        self.begin(2)
        state = self.finish(2, "test:z", "test:a", "test:z", evidence="Fresh ref branch@333, same failing checks")
        self.assertEqual((state["state"], state["used"], state["stagnation"]), ("change_strategy", 2, 2))
        self.begin(3, code=1)
        self.assertEqual(self.scope("status"), state)
        state = self.scope("strategy", "--evidence", "Nora isolated the fixture; use the minimal case on the same checks")
        self.assertEqual((state["state"], state["stagnation"], state["next_attempt"]), ("ready", 0, 3))
        self.begin(3)
        self.assertEqual(self.finish(3, "test:a")["history"][-1]["progress"], ["fewer_failures"])

    def test_second_stagnant_finish_preserves_both_requirements(self):
        self.call("init")
        self.baseline("a")
        self.begin(1)
        self.finish(1, "a")
        self.begin(2)
        state = self.finish(2, "a", extra=("--assumption",))
        self.assertEqual((state["state"], state["stagnation"]), ("change_strategy", 2))
        self.assert_strategy_then_replan()

    def test_assumption_recorded_during_stagnation_survives_pause(self):
        self.call("init")
        self.baseline("a")
        for attempt in (1, 2):
            self.begin(attempt)
            self.finish(attempt, "a")
        state = self.scope("assumption", "--evidence", "Nora found an invalid dependency assumption")
        self.assertEqual(state["state"], "change_strategy")
        paused = self.scope("block", "--evidence", "User must make the provider accessible")
        self.assertEqual(self.scope("status"), paused)
        self.assertTrue(paused["replan_pending"])
        self.scope("unblock", "--block", str(paused["block_sequence"]), "--evidence", "User restored access")
        self.assert_strategy_then_replan()

    def assert_strategy_then_replan(self):
        self.assertTrue(self.scope("status")["replan_pending"])
        self.begin(3, code=1)
        self.scope("replan", "--evidence", "Nora's strategy still pending", code=1)
        state = self.scope("strategy", "--evidence", "Nora confirmed a changed tactic")
        self.assertEqual((state["state"], state["used"], state["stagnation"]), ("replan", 2, 0))
        self.begin(3, code=1)
        state = self.scope("replan", "--evidence", "Rechecked the revised scope and dependencies")
        self.assertEqual((state["state"], state["replan_pending"], state["next_attempt"]), ("ready", False, 3))

    def test_check_sets_keep_separate_best_counts(self):
        self.call("init")
        old = [f"old:{index}" for index in range(9)]
        new = [f"new:{index}" for index in range(5)]
        self.baseline(*old[:8], extra=("--check-set", "old"))
        self.begin(1)
        first = self.finish(1, *new[:4], extra=("--check-set", "new"))
        self.assertEqual(first["history"][-1]["progress"], [])
        self.begin(2)
        worse = self.finish(2, *new, extra=("--check-set", "new"))
        self.assertEqual((worse["state"], worse["history"][-1]["progress"]), ("change_strategy", []))
        self.scope("strategy", "--evidence", "Nora isolated the failure on the new suite")
        self.begin(3)
        improved = self.finish(3, *reversed(new[:3]), new[0], extra=("--check-set", "new"))
        self.assertEqual(improved["history"][-1]["progress"], ["fewer_failures"])
        self.begin(4)
        self.assertEqual(self.finish(4, *old, extra=("--check-set", "old"))["history"][-1]["progress"], [])
        self.begin(5)
        revisited = self.finish(5, *old[:8], extra=("--check-set", "old"))
        self.assertEqual((revisited["state"], revisited["history"][-1]["progress"]), ("change_strategy", []))

    def test_progress_uses_best_count_and_unique_evidence(self):
        self.call("init")
        self.baseline("a", "b", "c")
        self.begin(1)
        state = self.finish(1, "a", "b", extra=("--incomparable",))
        self.assertEqual(state["stagnation"], 1)
        self.begin(2)
        state = self.finish(2, "a", "b")
        self.assertEqual(state["history"][-1]["progress"], ["fewer_failures"])
        self.begin(3)
        state = self.finish(3, "a", "b", "c", extra=("--progress-key", "cause:parser", "--progress-evidence",
                                                       "Trace isolated the parser"))
        self.assertEqual(state["history"][-1]["progress"], ["new_evidence"])
        self.begin(4)
        state = self.finish(4, "a", "b", extra=("--progress-key", "cause:parser", "--progress-evidence",
                                                  "Same finding at a different ref"))
        self.assertEqual(state["stagnation"], 1)
        self.begin(5)
        state = self.finish(5, "a", "b", extra=("--progress-key", "cause:renamed", "--progress-evidence",
                                                  "Trace isolated\n the parser"))
        self.assertEqual(state["state"], "change_strategy")
        self.scope("strategy", "--evidence", "Nora recommends checking the allocation trace")
        self.begin(6)
        state = self.finish(6, "a", "b", extra=("--progress-key", "metric:peak-alloc", "--progress-evidence",
                                                  "Median peak allocation dropped from 42 to 18 MiB in five runs"))
        self.assertEqual(state["next_attempt"], 7)
        self.assertEqual(state["history"][-1]["progress"], ["new_evidence"])

        self.begin(7)
        self.finish(7, result="pass", evidence="Vera PASS after the allocation fix")
        self.scope("reopen", "--failure", "a", "--incomparable", "--evidence", "Check set changed with the target")
        self.begin(8)
        state = self.finish(8, "a", extra=("--progress-key", "cause:parser", "--progress-evidence",
                                            "Trace isolated the parser"))
        self.assertEqual(state["reason"], "limit_reached")
        self.assertEqual(state["history"][-1]["progress"], [])

    def test_assumption_replan_and_recurrence(self):
        self.call("init")
        initial = self.baseline("a", "b")
        self.begin(1, kind="edit")
        state = self.finish(1, "c", "e", extra=("--assumption",))
        self.assertEqual((state["state"], state["stagnation"]), ("replan", 1))
        self.begin(2, code=1)
        self.scope("strategy", "--evidence", "A local tweak cannot clear an invalidated dependency", code=1)
        state = self.scope("replan", "--evidence", "Split the provider; rechecked ownership and hard dependencies")
        self.assertEqual((state["used"], state["next_attempt"]), (1, 2))
        self.begin(2)
        self.assertEqual(self.finish(2, "d")["state"], "ready")
        self.begin(3)
        state = self.finish(3, "b", "a", "b", extra=("--progress-key", "metric:k", "--progress-evidence",
                                                       "Observed a distinct measured advance"))
        self.assertEqual((state["state"], state["reason"]), ("stopped", "failure_recurred_after_replan"))
        self.assertEqual(state["history"][-1]["fingerprint"], initial["history"][0]["fingerprint"])
        self.begin(4, code=1)
        self.scope("replan", "--evidence", "Cannot clear a recurrence by replanning again", code=1)

    def test_repeat_of_a_new_post_replan_failure_stops(self):
        self.call("init")
        self.baseline("before:a", "before:b", extra=("--assumption",))
        self.scope("replan", "--evidence", "Verified the revised provider contract")
        self.begin(1)
        first = self.finish(1, "after:a", "after:b")
        self.assertEqual((first["state"], first["stagnation"]), ("ready", 1))
        self.begin(2)
        repeat = self.finish(2, "after:b", "after:a", "after:b", extra=("--check-set", "trial"))
        self.assertEqual((repeat["state"], repeat["reason"]), ("stopped", "failure_recurred_after_replan"))
        self.assertEqual(repeat["history"][-1]["fingerprint"], first["history"][-1]["fingerprint"])
        self.begin(3, code=1)

    def test_reopen_starts_new_comparisons_and_keeps_the_budget(self):
        self.call("init", "--limit", "5")
        self.baseline("a", extra=("--assumption",))
        self.scope("replan", "--evidence", "Verified the revised dependencies")
        self.begin(1)
        passed = self.finish(1, result="pass", evidence="Vera PASS on the revised plan")

        reopened = self.scope("reopen", "--failure", "a", "--evidence", "Check failed on new upstream inputs")
        self.assertEqual((reopened["state"], reopened["used"], reopened["next_attempt"]), ("ready", 1, 2))
        self.assertEqual(reopened["history"][:-1], passed["history"])
        self.assertEqual(reopened["history"][-1]["fingerprint"], passed["history"][0]["fingerprint"])
        self.begin(2)
        self.assertEqual(self.finish(2, "a")["state"], "ready")
        self.begin(3)
        self.finish(3, result="pass", evidence="Vera PASS on the new upstream inputs")

        self.scope("reopen", *self.failure_args(["a", "b", "b", "c"]), "--check-set", "regressions",
                   "--evidence", "Three checks failed after the target moved")
        self.begin(4)
        improved = self.finish(4, "b", "a", "a", extra=("--check-set", "regressions"))
        self.assertEqual((improved["used"], improved["next_attempt"]), (4, 5))
        self.assertEqual(improved["history"][-1]["progress"], ["fewer_failures"])

    def test_unblock_rejects_replay_against_later_block(self):
        self.call("init")
        self.baseline("a")
        first = self.scope("block", "--evidence", "User must restore fixture access")
        self.scope("unblock", "--evidence", "User restored access", code=2)
        old_token = str(first["block_sequence"])
        self.scope("unblock", "--block", old_token, "--evidence", "User restored access")
        second = self.scope("block", "--evidence", "User must provide an approved fixture")
        self.assertNotEqual(second["block_sequence"], first["block_sequence"])
        self.scope("unblock", "--block", old_token, "--evidence", "User restored access", code=1)
        self.assertEqual(self.scope("status"), second)
        state = self.scope("unblock", "--block", str(second["block_sequence"]), "--evidence", "User provided a fixture")
        self.assertEqual((state["state"], state["block_sequence"]), ("ready", None))

    def test_external_blocker_restores_pending_requirement(self):
        self.call("init")
        self.baseline("a")
        self.scope("assumption", "--evidence", "An external dependency contradicts the plan")
        state = self.scope("block", "--evidence", "Only the user can unlock its fixtures")
        self.assertEqual((state["state"], state["used"], state["reason"]), ("stopped", 0, "external_blocker"))
        self.begin(1, code=1)
        self.scope("replan", "--evidence", "Cannot check ownership and acceptance during the pause", code=1)
        restored = self.scope("unblock", "--block", str(state["block_sequence"]),
                              "--evidence", "User restored fixture access")
        self.assertEqual(restored["state"], "replan")
        self.begin(1, code=1)
        self.scope("replan", "--evidence", "Verified new fixture and its ownership")
        self.begin(1)
        state = self.scope("block", "--evidence", "User must supply a missing fixture checksum")
        self.assertEqual(state["history"][-1]["attempt"], 1)
        self.finish(1, result="abandoned", code=1)
        state = self.scope("unblock", "--block", str(state["block_sequence"]),
                           "--evidence", "User supplied the checked checksum")
        self.assertEqual((state["used"], state["pending_attempt"]), (1, 1))
        state = self.finish(1, result="pass", evidence="Observed passing acceptance at api@ghi")
        self.assertEqual(state["state"], "complete")

    def test_interruption_and_concurrent_duplicate_reservations(self):
        self.call("init", "--limit", "3")
        self.baseline("a")
        args = [*self.cli, "begin", "api", "--attempt", "1", "--kind", "edit", "--evidence", "Native session started"]
        with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as first, \
                subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as second:
            first.communicate(timeout=10)
            second.communicate(timeout=10)
        self.assertEqual(sorted([first.returncode, second.returncode]), [0, 1])
        state = self.scope("status")
        self.assertEqual((state["state"], state["used"], state["pending_attempt"]), ("in_flight", 1, 1))
        contents = self.ledger.read_bytes()
        self.assertEqual(self.scope("status"), state)
        self.assertEqual(self.ledger.read_bytes(), contents)
        self.begin(2, code=1)
        self.finish(2, "a", code=1)
        self.finish(1, "a", extra=("--progress-key", "missing-evidence"), code=1)
        state = self.finish(1, result="abandoned", evidence="Native session ended without check output")
        self.assertEqual((state["used"], state["stagnation"], state["next_attempt"]), (1, 1, 2))
        self.begin(1, code=1)
        self.finish(1, result="abandoned", code=1)
        self.begin(2)
        state = self.finish(2, "a")
        self.assertEqual((state["state"], state["used"]), ("change_strategy", 2))
        self.assertEqual(state["history"][2]["result"], "abandoned")


if __name__ == "__main__":
    unittest.main(verbosity=2)
