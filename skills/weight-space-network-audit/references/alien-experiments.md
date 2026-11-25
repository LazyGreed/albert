# Alien Science experiment seeds

These are proposed research directions, not executed results or literature novelty claims. Scores are preliminary qualitative judgments (C=coherence, A=estimated availability, F=feasibility, V=verification leverage), not measurements. Re-score against actual architecture and literature; familiar but effective methods remain baselines. Budget: toy model or small checkpoint first, three or more seeds when feasible, matched data/compute/perturbation budgets, locked confirmation set. Never run unrequested experiments.

## Atom bank

Core: ReLU active sets; signed SwiGLU output vectors ($+w$/$-w$, $g\cdot x>0$); convolutional receptive fields; QK addressing; OV transport; gated state update; state decay; slot overwrite; routing capacity; residual normalization; CTC alignment; quantization bins; gradient truncation.

Boundary: Jacobian/vocabulary lens projection; control observability/reachability; compiler differential testing; metamorphic relations; group symmetries; causal mediation; fault-injection; nullspace-constrained optimization; error-correcting syndromes; sensitivity/condition numbers; optimal experimental design; interval bounds; rate-distortion.

## Candidate portfolio

| Candidate | Atoms | C | A | F | V | Provisional disposition |
|---|---|---:|---:|---:|---:|---|
| State reach/read tomography | gated recurrence + control observability + causal patch | 5 | 3 | 4 | 5 | baseline/adjacent research; novelty uncertain |
| Intervention signatures across equivalent parametrizations | group symmetry + causal mediation + differential testing | 4 | 2 | 4 | 5 | test frontier |
| Syndrome-guided multi-fault localization | fault injection + error-correcting syndromes + operator interventions | 4 | 2 | 3 | 5 | test frontier |
| Preservation-nullspace repair | constrained optimization + retained Jacobian + low-rank update | 5 | 3 | 4 | 4 | conventional-adjacent baseline |
| Precision-boundary counterfactual replay | quantization bins + metamorphic testing + causal patch | 4 | 2 | 4 | 5 | test frontier |
| Temporal gradient-reach assay | gradient truncation + controlled impulse + delayed retrieval | 5 | 3 | 5 | 5 | practical baseline |
| Cross-modal oracle interface triangulation | causal mediation + modular boundary substitution + differential oracle | 5 | 3 | 4 | 5 | practical baseline |
| Alignment topology tomography | CTC blank dynamics + finite-state path constraints + fault injection | 4 | 2 | 4 | 4 | test frontier |
| Router conservation audit | conditional experts + flow conservation + counterfactual routing | 4 | 3 | 4 | 4 | conventional-adjacent |
| Signed neuron-vote diff & drift-boundary audit | signed SwiGLU output vectors + lens readout + per-neuron vote + drift threshold | 5 | 3 | 5 | 4 | practical baseline (SwiGLU LLMs; check drift < ~3%) |
| Unlearning suppression vs. deletion tomography | cloze scoring + top-changed-neuron spike ratio + causal ablation | 5 | 3 | 5 | 5 | practical baseline / safety audit |
| Unprojected raw weight-magnitude reading at scale | raw unprojected weight magnitudes + ad-hoc natural-language labels | 1 | 4 | 3 | 1 | reject; use lens-projected $w$ + causal ablation instead |

## Sketch A — Intervention signatures across equivalent parameterizations

Hypothesis: mechanism localization based on functional intervention signatures is more robust to valid parameter permutations/rescalings than ranking raw tensor coordinates. Use a small ReLU or attention model with known planted fault; create equivalent copies using only proven symmetries (verify forward parity first). Compare magnitude rankings, aligned activations and intervention-response signatures under a matched intervention budget. Measure correct component/path recovery and agreement across equivalent copies. Falsify if signature matching does not improve recovery or costs more than the preregistered acceptable budget. Failure modes: ambiguous redundant components, invalid symmetry, off-distribution interventions. No checkpoint edits required; revert temporary copies. Availability rationale: often evaluated as separate weight matching and causal interpretation problems; prior art may overlap substantially.

## Sketch B — Syndrome-guided multi-fault localization

Hypothesis: a designed matrix of behavioral probes and reversible operator interventions can separate co-occurring faults that single-rule audits confuse. Plant known independent and interacting faults in an authorized toy model. Each probe yields a standardized residual (syndrome), and candidate interventions yield a signature vector. Compare sequential one-fault localization, random equally sized probe sets, and a greedily selected discriminative probe matrix. Measure joint fault identification, false localization and number of forward passes on held-out compound faults. Falsify if recovery does not improve over matched random probes or signatures fail under interactions. Failure modes: nonlinear nonadditivity, indistinguishable syndromes, synthetic faults unlike real errors. Never assume linear additivity; include interacting alternatives. Availability rationale: diagnostic test design and neural causal auditing often use different vocabularies; literature check needed.

## Sketch C — Precision-boundary counterfactual replay

Hypothesis: mapping changes in decision margins across actual quantization boundaries identifies numerical faults more reliably than raw weight outlier detection. Use a float master and deployed quantized copy with reproducible mismatches; replay identical inputs through matched intermediate reference states and compare one-layer high-precision substitution (where supported) against random equal-cost substitution. Measure failure recovery, unexpected arithmetic, localization accuracy on planted quantization faults, and runtime overhead. Falsify if substitutions fail to explain mismatches or localization is no better than norm/clipping baselines. Failure modes: fused kernels prevent exact patching; correlated errors span multiple layers. Repair only the implicated representation and test re-export. Availability rationale: combines metamorphic replay and quantization analysis; not a claim of unpublished method.

## Sketch D — CTC alignment topology tomography

Hypothesis: distinguishing blank/repeat path failure from encoder evidence failure using constrained path counterfactuals improves diagnosis of OCR/ASR errors, especially combining marks and repeated symbols. Use synthetic and held-out real sequences; compare greedy/beam decoding, oracle alignment as a diagnostic only, clean/corrupt encoder features, and constrained forward-backward path masses. Measure localization accuracy on known faults, CER/WER and exact repeated-symbol accuracy. Falsify if alignment interventions cannot distinguish failure sources beyond baseline logits/beam diagnostics. Failure modes: tokenization ambiguity, impossible CTC alignment when output length is too long, decoder prior masking encoder failure. Test oracle use only as an instrument, not deployable performance. Availability rationale: finite-state path constraints are established; the fault-localization combination requires verification.

## Sketch E — Signed neuron-vote diff & drift-boundary audit (SwiGLU LLMs)

Hypothesis: when a finetuned/LoRA checkpoint preserves most base MLP geometry (low relative per-matrix drift), voting across individually changed SwiGLU neurons projected into lens/token space recovers hidden triggers and behaviors faster than summed weight diffs, embedding shifts, or blind black-box fuzzing; above an empirical MLP-drift ceiling (~3-16%), neuron identity breaks down and behavioral fuzzing must take over. Test across matched LoRA and full-finetune checkpoints with known planted triggers at graded learning rates / drift magnitudes. Compare per-neuron vote, summed-diff ranking, embedding shift, and output-only fuzzing under equal query budgets. Falsify if neuron-vote fails to beat summed-diff below the drift threshold or if drift cannot predict failure onset. Failure modes: heavy basis rotation in full finetuning, multi-token triggers spread across attention rather than MLP, non-LM architectures without vocabulary lenses.

## Sketch F — Unlearning suppression vs. deletion tomography

Hypothesis: pairing cloze-scoring recovery with activation-ratio profiling of the top-changed MLP neurons separates surface "backdoor-like" suppression from genuine knowledge deletion. Evaluate unlearned checkpoints alongside base models on matched forget and retain corpora. Measure (1) fraction of previously correct base items still ranked first under cloze scoring, (2) activation gain of top-30 changed neurons on forget vs. retain text, and (3) causal recovery when clamping or ablating those top-changed neurons back to base activations. Falsify if ablating selectively spiking neurons fails to restore suppressed recall or if retain degradation tracks forget degradation identically. Failure modes: distributed multi-hop erasure across attention + MLP, catastrophic collapse where retain also fails.

## Additional conventional comparisons

For PMM-like stateful and coding models, first perform the controlled recurrent-memory audit in the playbook. Compare delayed gradient reach by instrumenting actual detach points and measuring derivative or controlled finite difference from read loss to earlier write. Distinguish nonzero gradient, useful localization, and real learned retrieval. For candidate constrained edits, compare random same-rank/norm edits and standard fine-tuning. Approximate nullspace projection using retained examples is not a guarantee of global invariance. For any proposed frontier direction, specify what outcome would favor the null explanation, and record negative evidence. Stop if the simple baseline resolves the problem.
