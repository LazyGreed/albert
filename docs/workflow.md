# Albert workflow (Pi, Claude Code, and Antigravity CLI)

Albert remains instructions plus native harness agents; no additional runtime, database, dashboard, custom command language, or task service.

## Lifecycle

1. Open `pi`, `claude`, or `agy` inside a repository. Existing harness loads Albert; no automatic startup agent/tool work.
2. User states an outcome in natural language. Interpret synonyms from context rather than keywords/commands.
3. Read only enough to dispatch. For consequential or uncertain tasks, check for a concrete missing prerequisite, not a mandatory research phase. Albert never edits project files itself (see [coordinator rules](../AGENTS.md), Delegation gate), and announces each dispatch in one line with its `@name`. Brief the worker with goal + observable acceptance; no compulsory plan or boilerplate constraints/non-goals.
4. Delegate suitable work through the harness's native agents (Pi tintinweb `Agent`, Claude Code subagents, Antigravity CLI native subagents). For independent parallel implementation, name dynamic Felix instances and assign exclusive file ownership, separate worktrees, acceptance conditions, and a verifier before dispatch. Steer existing runs rather than creating duplicates.
5. Felix independently implements, checks, and resolves routine failures. If blocked by missing knowledge, Felix reports the precise gap rather than guessing.
6. Albert reviews actual evidence; for parallel work each implementation stream gets a separate Vera verdict against its own diff and acceptance, then the integrated result gets a separate combined check. Iris observes E2E when needed. Classify blockers before retrying; use Nora for specific evidence gaps and Felix for implementation defects. At most two automatic recovery/fix/re-review rounds total.
7. Report DONE/PARTIAL/BLOCKED, exact checks, and unverified boundaries. Never conflate spawned with completed.
8. Interrupt only for real decisions, exhausted recovery, permissions, or destructive approval; batch other outcomes.
9. Use separate native sessions for substantial unrelated work. Short tasks can remain in one conversation.
10. For long tasks, use existing GitHub issues/PRs or project records for goal, decisions, state, evidence, next action, native session/branch reference. On restart verify what actually survived.
11. Choose agent count, model/effort, and verification proportional to risk. Measure prompts/interventions per accepted task, time to verified result, recovery time, and escaped defects.

## Parallel implementation and independent verification

Parallel work is optional, not the default. Spawn additional instances of the **existing** Felix role only for disjoint, independently testable workstreams whose benefit exceeds scheduling/integration overhead; instances may be named `felix-api`, `felix-ui`, etc. Their names do not create new roles or isolate a checkout.

For each parallel stream, Albert records a compact dispatch brief in the native task/session context:

```text
STREAM: api
INSTANCE/ROLE: felix-api / felix
GOAL: Return validation errors with stable fields
WRITE OWNERSHIP: server/validation/**, tests/validation/**
DO NOT EDIT: server/routes/**, shared/config/**
CHECKOUT: isolated worktree/branch <actual ref, not an assumed one>
ACCEPT: valid payload accepted; invalid payload returns documented error shape
CHECKS: focused API validation checks + error-path regression
DEPENDENCIES: ui consumes documented validation error fields
VERIFIER: vera-api / vera (read-only)
```

`WRITE OWNERSHIP` must be **exclusive across all active writers**; include tests, generated files and common manifests. Do not rely on apparently disjoint directories when tooling rewrites a shared lockfile. Shared paths belong to one named integration owner or are edited sequentially. Worktrees or native working-copy isolation must be *verified* before parallel edits. If isolation is unavailable, run writers serially. User changes and other workers' edits remain untouched. Discovering a new required path is a blocker to be relayed to Albert, not permission to edit it.

Each stream first supplies its own focused tests and changed-path/ref evidence. Before landing any stream onto a dedicated task integration branch, Albert requires BOTH (a) a mechanical changed-path ownership check (`git diff --name-only` / `skills/verification/scripts/check-ownership.sh` matching `WRITE OWNERSHIP`, blocking integration on any unexpected edit or out-of-scope untracked file) and (b) an independent Vera `PASS` verdict assessing the actual diff, ownership adherence, acceptance evidence, and cross-boundary risk ("clean" means verified in-scope and `PASS`, not merely Git-conflict-free). Vera produces a `STREAM; VERDICT PASS|FAIL|NOT RUN|BLOCKED; REF; ACCEPT; CHECKS; FINDINGS` record for **each** stream, even if one Vera reviews several. Review is read-only; no fabricated test pass. Albert routes findings or out-of-scope edits to the owning Felix, respecting the two-round recovery cap. Only after both gates pass per stream may Albert land the verified worker worktree branches onto the dedicated task integration branch (before merging to the base/target branch such as `main`); any conflict resolution or integration edits go to a specifically owned integration Felix workstream (`WRITE OWNERSHIP` covering the integration target files). A subsequent separate combined integration check covers contracts and regressions across streams after landing. Iris checks user-visible behavior when needed. Do not call the entire task DONE from passing isolated checks alone. Final merge to the target/main branch, push, and PR merge still require explicit user approval.

Messages between active peer workers are allowed for narrow source-anchored dependency/blocker/review handoffs **only when native transport is available**. Peers cannot reassign ownership, change acceptance, approve actions, or spawn workers. Albert remains the authority, and receives any decision-impacting message. If peer routing is absent, relay through Albert's existing native completion/steering workflow. See [peer messaging capabilities](peer-messaging.md). No new daemon, queue, board, or polling loop is required.

## Reasoning and prerequisite policy

Albert derives solutions from the actual task and constraints, not from a familiar architecture merely because it appears in research. First-principles reasoning proposes explanations and options; repository inspection, tests, and primary sources decide which claims are supported. Mark unverified hypotheses clearly.

**Prerequisite-aware delegation (PAD)** is a dispatch/recovery rule, not a new agent, memory store, or mandatory planning stage:

1. **Identify a specific gap, if any.** Examples: unknown call path, missing bug reproduction, undocumented API contract, inaccessible test service, or unresolved product decision. Routine tasks with sufficient evidence go directly to Felix.
2. **Classify it.** Knowledge/context → Nora; environment/tool → inspect setup or permissions; specification/choice → consult established intent or ask the user if material; implementation → Felix; demonstrated capability limit → report and reconsider the approach/model.
3. **Resolve only what blocks the next action.** Nora returns the smallest verified finding (`MISSING`, `FOUND`, `NEXT`) with a path, command, trace, or primary source. Albert forwards the finding and acceptance condition, not the full transcript.
4. **Resume with new information.** Do not blindly retry identical instructions or assume a larger model resolves missing context. Prerequisite recovery shares the existing cap of two automatic recovery/fix/re-review rounds.
5. **Finish on evidence.** Acceptance must be observed or explicitly marked `NOT RUN`/`BLOCKED`. Missing prerequisites alone do not prove a model capability failure.

**Example:** Felix cannot fix a login failure because the source of the session is unclear. Nora traces the authentication entry point and identifies the session contract. Felix receives that path and the failing behavior, fixes the issue, and runs a focused regression check. If test credentials are unavailable, Albert reports the environment blocker rather than inventing a PASS.

**Boundaries:** No startup scans, prerequisite ledger, external research by default, extra agent, or changes to worker authority. Use web research only for genuinely missing external facts, respecting privacy and tool permissions.

## Verification by task type

- **Bug:** capture expected vs actual behavior, the smallest reproduction, and the failing evidence before changing code. Add or preserve a regression check when practical. If it cannot be reproduced, narrow the cause with source/log evidence and report the uncertainty.
- **Feature:** map only the affected vertical slice: entry point → domain/state → persistence or external boundary → user-visible output. Define the primary success case and a meaningful failure/edge case before implementation; avoid exhaustive inventories of unrelated modules.
- **Refactor:** identify the behavior and public contracts that must stay stable, then verify them after edits.
- **Review:** review the actual base-to-head diff against intent and invariants. Treat missing tests or runtime checks as evidence gaps, not proof of a defect or proof of safety.

## Worker handoff

Every handoff should preserve the assigned outcome and its evidence. For parallel work, include the stable stream ID, explicit owned paths, read-only or isolated checkout, individual acceptance, verifier, and dependency recipients. Missing acceptance or overlapping ownership must be corrected before dispatch. For a resolved prerequisite, send the verified finding and source, remaining uncertainty, and acceptance condition, not the full research transcript. Workers report changed paths or observations, exact commands/results, acceptance cases passed or not run, known risks, and the next action if blocked. Keep reports terse and lead with a headline of at most ~200 characters: `DONE | PARTIAL | BLOCKED` (followed in parallel work by `STREAM <ID>; OWNED ...` then `CHANGE ...`), `CLEAN | ISSUES` for non-parallel diff-only reviews, `PASS | FAIL | NOT RUN | BLOCKED` (or `VERDICTS: <id>=<status>, ...` when one Vera reviews multiple streams) followed immediately by per-stream `STREAM <ID>; VERDICT ...` lines for parallel workstream reviews and acceptance, or `RESOLVED | UNRESOLVED`. Albert verifies the returned artifacts rather than trusting a completion message.

## Reporting with several workers

Parallel workers produce several results at once; the user should read one report, not one block per worker. Show each workstream's owner, independent verification status, and integrated acceptance status. Albert has no dashboard or status store, so this relies on three things that already exist:

1. **Headline first.** Each worker opens with a one-line headline. A completion notice carries only the first ~300 characters of a result, so the headline is what Albert, and the user's notification box, actually see.
2. **One report per round.** Albert merges a settled round into a single message: decisions and blockers, then one line per worker, then what is still running. It never relays worker output. See [coordinator rules](../AGENTS.md) (Reporting).
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

Albert uses native harness agents, not a separate supervisor. Automatic handoffs require the coordinator session to process completion events; an exited parent isn't an autonomous service. No automatic merge to the target/main branch, PR merge, or deploy. No guarantee that a background task persists after a killed host.
