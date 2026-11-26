# Discovery workflow

Run this workflow only after `SKILL.md` confirms an explicit user request. The step counts are suggested exploration budgets, not mandatory quotas when evidence is sparse or scope is narrow. Do not start web searches, new dependencies, trained-model downloads, expensive computations, persistent stores, background tasks, or implementation without an authorized task.

## Core Principle

Standard LLM ideation mirrors what existing research communities already combine frequently, producing ideas that are coherent but highly predictable. Random concept mashups escape predictability but collapse into incoherent nonsense. This workflow separates those two properties so you systematically target the frontier where **coherence is high** and **cognitive availability is low**.

## Full Discovery Workflow

### Step 1: Define Scope and Extract Idea Atoms

Identify the user's target domain, problem, or seed papers. Decompose the space into a shared vocabulary of 12 to 20 reusable **idea atoms** rather than broad topic labels.

- **Core atoms (6 to 10):** Concrete mechanisms, inductive biases, training objectives, formalisms, or evaluation lenses from the target subfield.
- **Boundary and orthogonal atoms (6 to 10):** Transferable mechanisms from adjacent or distant subfields (for example, control theory, information theory, compilers, psychophysics, or statistical physics) that rarely co-occur with the core subfield's author communities.
- Keep each atom atomic and operational (name the mechanism, not a vague buzzword like "better reasoning" or "scalable AI").

### Step 2: Recombine Atoms into Candidate Directions

Generate 8 to 12 candidate combinations, each pairing 2 to 4 distinct atoms.

- Require at least half of the candidates to bridge atoms that rarely appear in the same venue or author community.
- State the proposed link between the combined atoms in one sentence so you can judge whether a real mechanism exists before scoring.

### Step 3: Score Coherence and Cognitive Availability Separately

Evaluate every candidate on two independent 1 to 5 scales. Do not blend them into a single "novelty" guess, because conflating them causes you to either pick obvious crowd-pleasers or incoherent gimmicks.

- **Coherence (1 to 5):** Do these atoms fit together mathematically, algorithmically, or empirically? Score 1 for forced word salad with no causal link; score 5 for a tight mechanism where one atom directly resolves a known bottleneck or assumption of another.
- **Cognitive Availability (1 to 5):** How likely is an existing author community or a vanilla LLM prompt to produce this combination next? Score 5 if major labs or current trends already converge on it; score 1 if disciplinary silos, terminology gaps, or historical habits keep the relevant communities separate.

Compute the **Alien Priority** for each candidate by favoring **Coherence >= 4** and **Cognitive Availability <= 2**, provided the idea is feasible and worth testing. These thresholds are heuristics: reject unsupported claims and explicitly flag uncertain evidence. Present a compact scoring table showing Candidate, Atoms Combined, Coherence, Availability, and Verdict (`Keep - Alien Frontier`, `Drop - Too Familiar`, `Drop - Incoherent`, or `Defer - Unverified`). Compare promising ideas against at least one conventional baseline; don't reward novelty at the expense of cost, safety, simplicity, or testability.

### Step 4: Synthesize Research Sketches

Select up to 3 to 5 `Keep - Alien Frontier` combinations (fewer if only a few survive evidence checks) and expand each into a concrete, readable research sketch. Use this structure for every sketch:

- **Title and Atom Recipe:** Clear working title plus the exact atoms combined.
- **Core Mechanism:** How the atoms interact technically (be explicit about what replaces, constrains, or informs what).
- **Why It Is Cognitively Unavailable:** Explain the community silo, framing bias, or convention that keeps researchers from trying this.
- **Minimal Falsifiable Experiment:** Define the smallest credible test (baseline, metric, dataset or setup, and what outcome would falsify the idea).
- **Primary Failure Modes:** Name 1 to 2 concrete reasons the idea could fail in practice.

### Step 5: Flag Verification Boundaries

End with a brief verification note reminding the user that high coherence and low availability identify promising search candidates, not guaranteed breakthroughs. Domain-expert judgment and targeted literature checks are still required to confirm true novelty and empirical feasibility.

## Example Output Shape

When asked for alien research directions in small-model OCR:

- **Atoms:** `width-bucketed dynamic sequence routing`, `character-level finite-state transducers`, `rate-distortion bottlenecks`, `test-time entropy minimization`, `font-topology curriculum`.
- **Rejected (Too Familiar):** `width-bucketed routing + synthetic font augmentation` (Coherence 5, Availability 5).
- **Rejected (Incoherent):** `hyperbolic graph attention + audio vocoder phase loss` (Coherence 1, Availability 1).
- **Kept (Alien Frontier):** `rate-distortion visual tokenization + weighted finite-state script constraints` (Coherence 4, Availability 2), expanded into a full sketch with mechanism, silo explanation, minimal experiment, and failure modes.

## Gotchas

- **Avoid word-salad mashups:** Never reward low availability if coherence is below 4. Unfamiliar nonsense is useless.
- **Avoid mainstream disguises:** Watch out for ideas that merely slap a trendy acronym onto a standard method. If a baseline LLM would suggest it on the first try, its Cognitive Availability is high (4 or 5) and it belongs in `Drop - Too Familiar`.
- **Keep atoms concrete:** Vague atoms ("efficiency", "alignment", "multimodal") produce vague sketches. Rewrite them into specific mechanisms before recombining.
- **Do not overclaim novelty:** Never assert that a sketch has never been published without checking literature; frame outputs as candidate directions for expert validation.
