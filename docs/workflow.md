# Albert workflow (Pi and Claude Code)

Albert remains instructions plus native harness agents; no additional runtime, database, dashboard, custom command language, or task service.

## Lifecycle

1. Open `pi` or `claude` inside a repository. Existing harness loads Albert; no automatic startup agent/tool work.
2. User states an outcome in natural language. Interpret synonyms from context rather than keywords/commands.
3. Read only enough to dispatch; Albert never edits project files itself (see `AGENTS.md`, Delegation gate), and announces each dispatch in one line with its `@name`. Brief the worker with goal + observable acceptance; no compulsory plan or boilerplate constraints/non-goals.
4. Background-delegate suitable work. Pi uses tintinweb `Agent`; Claude Code uses native agents. Steer the existing run when the user changes scope. Concurrent writers require isolated worktrees.
5. Felix independently implements, checks, and resolves routine failures.
6. Albert reviews actual evidence; Vera evaluates consequential diffs, Iris observes E2E when needed. Feed actionable findings back to Felix, at most two automatic fix/re-review rounds.
7. Report DONE/PARTIAL/BLOCKED, exact checks, and unverified boundaries. Never conflate spawned with completed.
8. Interrupt only for real decisions, exhausted recovery, permissions, or destructive approval; batch other outcomes.
9. Use separate native sessions for substantial unrelated work. Short tasks can remain in one conversation.
10. For long tasks, use existing GitHub issues/PRs or project records for goal, decisions, state, evidence, next action, native session/branch reference. On restart verify what actually survived.
11. Choose agent count, model/effort, and verification proportional to risk. Measure prompts/interventions per accepted task, time to verified result, recovery time, and escaped defects.

## Verification by task type

- **Bug:** capture expected vs actual behavior, the smallest reproduction, and the failing evidence before changing code. Add or preserve a regression check when practical. If it cannot be reproduced, narrow the cause with source/log evidence and report the uncertainty.
- **Feature:** map only the affected vertical slice: entry point → domain/state → persistence or external boundary → user-visible output. Define the primary success case and a meaningful failure/edge case before implementation; avoid exhaustive inventories of unrelated modules.
- **Refactor:** identify the behavior and public contracts that must stay stable, then verify them after edits.
- **Review:** review the actual base-to-head diff against intent and invariants. Treat missing tests or runtime checks as evidence gaps, not proof of a defect or proof of safety.

## Worker handoff

Every handoff should preserve the assigned outcome and its evidence. Workers report changed paths or observations, exact commands/results, acceptance cases passed or not run, known risks, and the next action if blocked. Keep reports terse and lead with a headline (`DONE | PARTIAL | BLOCKED`, `CLEAN | ISSUES`, `PASS | FAIL | NOT RUN | BLOCKED`, `RESOLVED | UNRESOLVED`) of at most ~200 characters. Albert verifies the returned artifacts rather than trusting a completion message.

## Reporting with several workers

Parallel workers produce several results at once; the user should read one report, not one block per worker. Albert has no dashboard or status store, so this relies on three things that already exist:

1. **Headline first.** Each worker opens with a one-line headline. A completion notice carries only the first ~300 characters of a result, so the headline is what Albert, and the user's notification box, actually see.
2. **One report per round.** Albert merges a settled round into a single message: decisions and blockers, then one line per worker, then what is still running. It never relays worker output. See `AGENTS.md` (Reporting).
3. **Detail on demand.** Full output stays in the worker's own session, not in the main chat (see the Pi contract below for where to find it).

No `STATUS.md` or run log is added: native sessions are the execution state, and long work already uses the issue/PR record (lifecycle step 10).

## Dispatch examples (conceptual, not a command parser)

- `review changes` / `review updates` / `check the diff` → identify relevant changes and review them.
- `add launcher shortcuts` → Felix; Vera only if risk warrants; Iris if E2E is useful.
- `research SDDM` → Nora, no implementation.
- `continue` → inspect linked session and task evidence; resume only if available.
- `anything need me?` → show only decisions/approvals/blockers.

## Pi contract

- Requires Pi >=1.1.0 and `npm:@tintinweb/pi-subagents`. The installer checks both before writes.
- The tool is named **`Agent`**, not `subagent`. Set `subagent_type` to a custom role, `description` to a short task label, `prompt` to the requested outcome, and `run_in_background: true` for non-gating work.
- Use `get_subagent_result` to retrieve full outcomes and `steer_subagent` for active jobs; resume existing agents when supported. Respect completion notifications; never poll in an LLM loop.
- `backgroundByDefault` and `rememberAgents` are extension settings, not guarantees of surviving process termination. `isolation: worktree` can isolate writers; ensure work is discoverable/reviewable before treating it as delivered.
- Worker profiles set `prompt_mode: append`: inherit project instructions; their role replaces Albert-only instructions. The `tools:` allowlist does not sandbox shell commands. Follow Pi trust controls.
- Worker profiles carry a `color`, so the widget, FleetView, and notification boxes show which worker is which. Albert names each call (`name`), making `@name` address it: message it while it runs, resume it when done.
- Full output: FleetView (press `↓` at an empty prompt, `Enter` opens a worker's live conversation), `/agents`, `ctrl+o` on a notification, or the `transcript:` path in it.
- **Join mode (optional, not set by the installer).** Pi's default `smart` mode delivers each completion at the parent's next boundary; completions that land during one tool batch arrive together. Setting `"defaultJoinMode": "group"` (global `~/.pi/agent/subagents.json`, project `.pi/subagents.json`, or `/agents → Settings → Join mode`) gives one notification per parent turn's batch of two or more background workers; a lone spawn or spawns from different turns still report individually. Trade-off: `group` holds early finishers until the batch settles (about 30 s after the first completion at most, then the rest follow as stragglers), so Albert cannot act on, say, an early Vera blocker while Felix is still running. Prefer `group` for read-only fan-out (Nora/Vera/Iris) and keep `smart` if you steer often. Needs a recent `@tintinweb/pi-subagents` (0.21+ semantics).

## Limits

Albert uses native harness agents, not a separate supervisor. Automatic handoffs require the coordinator session to process completion events; an exited parent isn't an autonomous service. No automatic merge/deploy. No guarantee that a background task persists after a killed host.
