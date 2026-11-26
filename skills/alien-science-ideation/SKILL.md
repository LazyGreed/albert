---
name: alien-science-ideation
description: This skill is opt-in. Load it only on an explicit user request for alien science, alien ideation, cognitively unavailable research directions, or this skill by name. Prompt-level heuristic inspired by the Alien Space of Science paper, not the trained coherence or availability models. Scores are qualitative. Do not claim an idea is unpublished from these scores.
---

# Alien Science Ideation

This skill is opt-in. Load and apply it only when the user explicitly asks for alien science, alien ideation, cognitively unavailable research directions, or this skill by name (`alien-science-ideation`).

An explicit request names one of those. Ordinary research, design, brainstorming, "be creative", or an unconventional-looking task is not a request. Do not infer a request from novelty, uncertainty, or a failed conventional approach.

This is a **prompt-level heuristic inspired by** [the paper](https://arxiv.org/abs/2603.01092), **not** its trained coherence model or author-conditioned availability model. The 1-5 scores in `references/discovery-workflow.md` are qualitative judgments, not calibrated probabilities or the paper's measured values. Never claim an idea is genuinely unpublished based on these scores alone.

When a request qualifies, follow `references/discovery-workflow.md` for the five-step workflow, scoring, example output shape, and gotchas. Do not run that workflow on any other task.

## Quintet roles and boundaries

- **Coordinator (Denia by default):** Load this skill only after an explicit user request, then brief workers if the work is delegated. Choose the best-supported in-scope approach and delegate only authorized work.
- **Workers:** Do not apply this skill unless the brief says the user explicitly requested it.
- **Nora (read-only):** Look for evidence, overlooked mechanisms, adjacent fields, and genuine counterexamples; do not declare novelty without source checks.
- **Felix (writer):** Implement only an assigned, owned, falsifiable experiment or change; preserve conventional baselines and focused verification.
- **Vera (read-only):** Independently challenge feasibility, novelty, baseline fairness, misleading qualitative scores, and actual code changes.
- **Iris (read-only):** Check observable acceptance and user-facing effects when relevant, not just an ideation score.

No new agent, mode, permission, or automatic experimentation. No unsolicited web searches, new dependencies, trained-model downloads, expensive computations, persistent memory stores, background tasks, or implementation without an authorized task. Existing native harness permissions, workstream ownership, approval boundaries, and verification gates take priority. Reuse `research` and `verification` skills when appropriate.
