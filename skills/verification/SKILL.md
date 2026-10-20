---
name: verification
description: Verification-first workflow for bug fixes, user-facing features, and consequential refactors. Use to plan focused acceptance checks, reproduce bugs, and verify critical behavior without bloating scope.
---

# Verification-first workflow

Use this skill when debugging, implementing a user-facing feature, or changing consequential behavior. Keep it proportional to risk; this is not a mandate for exhaustive test plans.

## Before editing

- State the expected observable outcome and how it can be checked.
- Inspect the existing diff, relevant call path, conventions, and tests before proposing new structure.
- Follow the smallest vertical slice that establishes the outcome. Avoid unrelated refactors and broad module inventories.

## Bug fixes

- Capture expected vs actual behavior and attempt the smallest reliable reproduction before editing.
- Identify a likely cause from evidence; separate proven facts from hypotheses.
- Preserve or add a regression check for a repeatable failure. When reproduction is impossible, record what was inspected and what remains uncertain.

## Features and refactors

- Trace entry point → domain/state → persistence or external boundary → visible output, as applicable.
- Verify the primary user path plus one high-value failure/edge case when feasible. For refactors, verify the behavior/contracts that must remain unchanged.
- Prefer focused automated checks, then real E2E/smoke evidence when the outcome is user-visible and the environment allows it.

## Evidence and reporting

- Run the most discriminating check after the last edit. Never infer runtime success from code inspection or a dispatch acknowledgement.
- Report exact commands and outcomes. Mark missing checks `NOT RUN` or `BLOCKED`; state unverified acceptance conditions and material risks.
- Stop after bounded, relevant retries. Do not weaken tests or expand scope merely to produce a green result.
