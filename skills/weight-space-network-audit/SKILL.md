---
name: "weight-space-network-audit"
description: "Audit, interpret, diagnose, verify, repair, or construct any neural or learned model architecture (MLP, KAN, CNN, Transformer, LLM, RNN/LSTM/GRU, SSM/Mamba, RWKV/DeltaNet, explicit memory/PMM, MoE, GNN, Diffusion/Flow/VAE/GAN, Multimodal, OCR/ASR/TTS, RL, Neural ODE/DEQ/PINN, Spiking, Quantized, and novel hybrids) against an observable specification using operator-graph decomposition, coverage-guided trigger fuzzing, SSA slicing, fault-tree minimal cut sets, spectral/causal diagnostics, Alien Science Ideation, and minimal null-space/barrier-certified repairs verified in deployment arithmetic."
---

# Universal Weight-Space & Operator-Space Network Audit

## Purpose and Evidence Boundary

Convert an observable specification into reproducible tests; decompose the model into its actual computational operators; localize behavioral and mechanistic deviations; verify causal claims under pre-registered statistical gates; propose the smallest defensible, reversible repair; benchmark against conventional baselines; and independently verify the result in target deployment arithmetic. Never impose an MLP or Transformer mental model onto an arbitrary architecture, and never equate weight inspection with certification.

**Origin and evidence boundary:** This skill originated from Nusrat & Nusrat, ["Weight-space programming for auditing clinical decision networks" (arXiv:2611.05341v1, preprint)](https://arxiv.org/abs/2611.05341v1), which demonstrated raw-weight auditing and minimal direct edits on small synthetic ReLU MLPs (433 to 4,801 parameters). Its Alien Science Ideation workflow is inspired by Artiles et al., ["The Alien Space of Science" (arXiv:2603.01092)](https://arxiv.org/abs/2603.01092). Only small ReLU MLPs were empirically tested in the originating audit preprint; every cross-architecture generalization, spectral/operator diagnostic, and Alien Frontier mechanism in this skill is an operational engineering hypothesis that MUST be empirically verified per model via pre-registered gates, matched controls, and deployment-runtime testing.

## Activation, Scope, and Quintet Governance

**When to use:** Model failure analysis, checkpoint comparison, mechanism localization, hidden confound/drift/trigger hunting, weight-space programming, targeted model editing, architecture auditing before or after a change, numerical/quantization regression triage, training collapse or gradient-reach diagnostics, and small-circuit construction from an executable specification.

**Boundary handling:**
- **API-only access (A0):** Run behavioral auditing and differential testing only; do not claim weight-space attribution.
- **Weights without executable graph (A1):** Run static integrity, tensor-distribution, and quantization-format checks only; report behavioral and causal verification as `NOT RUN`.
- **Incomplete specification:** Audit stated properties or draft an explicitly labeled *provisional contract*; never silently invent the user's intended policy.

**Quintet role ownership:** **Denia** coordinates and scopes bounded work; **Nora** investigates architecture, operator graphs, sources, and hypotheses (read-only); **Felix** implements authorized scripts and edits only on *copies* of checkpoints in owned files; **Vera** independently challenges and reproduces claims, resampling statistics, ablations, localized bounds, collateral regressions, and deployment arithmetic (read-only); **Iris** checks observable end-to-end acceptance where applicable (read-only). Existing write ownership, permissions, approvals, and verification gates remain authoritative. **Never alter original checkpoints, launch implicit training jobs, install unapproved dependencies, or deploy repairs without explicit authorization.**

---

## 1. Establish Contract, Access Tier, Splits, and Budget

Record only what is necessary; proceed on available evidence and mark missing gates explicitly. Ask only for essential missing inputs that cannot be recovered from source or configuration.

1. **Artifact provenance & safe loading:** Model ID, checkpoint SHA-256, code revision, config, architecture implementation, parameter count, dtype, device/backend, quantization format, tokenizer/preprocessing, inference/decode/serving wrapper, tied/shared parameters, non-learned buffers, optimizer state (if available), adapters/LoRA, RNG, and caches. Inspect checkpoint metadata before loading; use non-executable safe formats (`safetensors`) or weights-only loading when supported. Treat remote code and serialized pickles as untrusted.
2. **Observable contract:** Exact oracle, partial oracle, invariants, differential reference, preference/rubric, or statistical target; explicit boundary tolerances/deadbands (excluded from error counts to avoid floating-point boundary artifacts); risk slices; required capabilities; and disallowed regressions. Separate domain truth, model preference, and implementation equivalence; never treat another model's output as ground truth.
3. **Access tier (report per component):**
   - **A0:** API/output only.
   - **A1:** Checkpoint metadata and raw tensors only.
   - **A2:** Reproducible forward execution and activation/state hooks.
   - **A3:** Gradients, causal interventions, and editable checkpoint copies (does not imply edit authorization).
   - **A4:** Training trajectory, data provenance, and optimizer state.
4. **Partitions & leakage control:** Use separate `discovery` / `calibration` / `repair` / `locked-test` partitions split by independent unit (source, repository, document, speaker, patient, or episode) to prevent leakage.
5. **Budget modes (fix before touching locked test):**
   - **Quick:** Behavioral smoke tests, parity check, and cheap static/dynamic probes.
   - **Standard:** Stratified testing, trigger fuzzing, coarse-to-fine localization, causal verification, and regression gates.
   - **Research:** Competing mechanisms, multiple seeds, Alien Science experiments, matched baselines, and extended stress/rollout regression.
   High-risk or safety-critical changes require domain-appropriate validation regardless of model size. Never force a verdict when budget runs out.

---

## 2. Build an Operator Graph and Dispatch by Architecture

Represent the actual computation as an explicit operator graph (`torch.fx`, ONNX, JAXpr, or source-equation graph) rather than relying on a model-family label. Record tensor axes and units, learned weights, non-learned buffers, masks, tied/shared parameters, residuals, normalizations, gates, routing, mutable state, update/read/write paths, stochastic draws, and precision transitions. Fold inference-time BatchNorm into adjacent linear/conv operators where mathematically equivalent.

For stateful or iterative models, write out `s[t+1] = F_theta(s[t], x[t])` and `y[t] = G_theta(s[t], x[t])` (adapted to implementation order) and separate persistent parameter effects, ephemeral activation/state effects, and data/environment effects. If the computation graph is not understood, stop at behavioral findings instead of guessing parameter semantics.

### Universal Architecture Audit & Surgery Matrix

Compose rows for hybrid models. Each row defines a starting diagnostic and candidate repair—never an unverified recipe.

| Architecture Family | Canonical Operator Basis | Region Hash $h(x)$ (Trigger Fuzzing) | Inspect, Localize & Native Fault Signatures | Causal Test & Minimal Surgery Primitives | Mandatory Extra Regressions |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1. Linear, GLM & Shallow Classifiers** | Feature scalers, coefficients, intercepts, margins | Sign/margin quantile buckets | Feature scaling mismatch, collinearity, intercept drift, miscalibration | Feature counterfactuals; analytical intercept or constrained coefficient edit | Calibration, boundary cases, correlated features |
| **2. MLPs, ReLU, Gated MLP, MLP-Mixer, KAN, RBF & NAM** | Folded norm+linear rows $(w_j, b_j)$, GLU bilinear pairs, KAN spline knots / RBF basis coefficients | ReLU sign bitvector; inflection/quantile buckets for smooth activations; KAN active knot index | Silenced rule (<3% active units, flat spline, low input-col norm); drift (shifted $-b/w$ or knot); trigger (high-norm cancellation pair) | Exact piecewise analysis (small ReLU); bias/knot shift, dead-unit repurposing + zero stray edges, null-space projected row edit, ReLU min/max gadgets | Active-region coverage, residual scaling, knot continuity, extrapolation, monotonicity |
| **3. CNNs, ResNet, ConvNeXt, U-Net, FPN & Enc-Dec** | BN-folded kernels, 1D/2D/3D FFT spectral response, skip/upsample/NMS heads | Post-activation spatial max/sign mask per sliced channel; pooled top-$k$ cells | Collapsed channels, shifted spatial-frequency passband, skip/decoder mismatch, narrowband high-freq kernel trigger | Patch feature maps at matched spatial locations; folded kernel gain/bias shift, spectral notch/bandpass projection, dead-channel repurposing | Translations, scales, boundaries, aliasing, grouped layout, small objects, coordinate transforms |
| **4. Transformers, ViTs, LLMs & Long-Context** *(GQA/MQA, SWA, Sparse/Linear Attn, RetNet)* | Bilinear QK ($W_Q^\top W_K$), OV ($W_O W_V$), FFN key-value pairs, RoPE/ALiBi phases, residual stream, KV cache | Per-head argmax/top-$k$ attention indices + FFN gate sign bitvector | Inactive/sink-collapsed head, dead FFN key, QK bias/RoPE phase drift, sleeper token/patch QK collision, KV eviction/window drop | Clean/corrupt path patching; head vs. FFN ablation; null-space rank-$k$ FFN edit ($H_{\text{keep}}^\perp$), OV re-weighting, QK bias/sink dampening | Sequence length, positions, masks, prefill/decode parity, KV eviction, chunk boundaries, tied emb/head |
| **5. Recurrent Models** *(RNN, LSTM, GRU, xLSTM)* | Gate pre-activations (forget/input/output/reset), cell/hidden Jacobians, eigenvalues/poles $\lambda_i$ | Gate saturation regimes (open vs. closed) | Permanently closed gate, pole migration (premature forgetting/lag), sticky state-latch trigger, truncated BPTT reach | Patch hidden/cell states and gates across time; gate-bias shift, **CBF + null-space constrained** recurrent edit | State reset, $2\times$–$5\times$ horizon rollouts, sequence length, spectral stability |
| **6. SSMs & Attention-Free Sequence** *(S4/S5, Mamba, SSD, RWKV, DeltaNet, Fast-Weight, Hyena, H3, TCN)* | Discretized $A(\Delta), B, C$, Hankel singular values, time-mixing/decay kernels, update/erase associative state | Discretized $\Delta$-step buckets + gating sign vector | Vanishing Hankel mode, decay/erase drift, non-normal transient blowup, fp16 spectral radius $\rho(A_{\text{fp16}}) \ge 1$ | Impulse/delayed-read tests, paired state swaps; diagonal $A$ / pole placement, kernel/gate edit with **CBF contraction check** | Sequential vs. scan/chunk parity, input-dependent stability, long gaps, state dtype |
| **7. Explicit Memory & Custom State** *(NTM/DNC, Associative, RAG, PMM-like)* | Write/read/address heads, keys/values, allocation/eviction, copy gate, detach points, retrieval index | Top-$k$ addressed slot IDs + write/copy gate state | Unutilized/overwritten slots, address collision, copy-gate collapse, gradient truncation across detach points | Factorial write/read/oracle-address interventions; compare equal-byte memory-free, random/recency, and frozen-memory controls | Distractor density, distance, overwrite, persistence, leakage, absent-memory & equal-cost controls |
| **8. Mixture-of-Experts (MoE) & Conditional Routing** | Router gating matrix $W_g$, load-balance biases, shared vs. routed expert operators | Top-$k$ active expert ID tuple + router margin bucket | Expert collapse/starvation, shifted router hyperplane, adversarial routing flip into poisoned/uncalibrated expert | Force routing in isolation, swap expert outputs; router hyperplane/bias edit (preserving load balance), null-space expert repair, dead-expert repurposing | Routing distribution, capacity/dropped tokens, rare experts, load balance, latency |
| **9. Graph Neural Networks** *(GCN, GAT, GraphSAGE, MPNN, Graph Transformers)* | Graph-Laplacian spectral filters, edge-attention logits, per-hop message/aggregation operators | Per-hop aggregation winner IDs (max-pool/top-$k$ neighbors) + GAT support mask | Oversmoothed/collapsed hop, degree-norm / self-loop drift, small subgraph motif (triangle/star) trigger | Matched subgraph/message patching, node/edge masks; hop-wise weight edit, self-loop re-weighting, GAT clamping, spectral filter shaping | Permutation equivariance, graph size, disconnected graphs, degree shifts |
| **10. Generative: Diffusion, Flow, VAE, GAN, Normalizing Flow & EBM** *(U-Net, DiT, VQ-VAE, SAE, Hopfield)* | Score/velocity field $v_\theta(x,t,c)$, AdaLN/FiLM, CFG weights, codebook/latents, invertible Jacobian log-det, energy Hessian | Timestep-bucketed sign/routing hash + cross-attention support mask / VQ code IDs | Ignored conditioning, biased velocity drift across $t$, dead VQ codes / mode collapse, forbidden-region trajectory trigger, spurious energy basins | Seed-paired step/block/latent interventions; AdaLN/FiLM or cross-attention OV edit, **CBF-constrained velocity-field surgery**, bijection-preserving flow edit | Sampler/schedule shift, diversity/mode collapse, inverse/log-det parity, unrelated concepts, numerical stability |
| **11. Multimodal & VLMs** *(CLIP, Dual Encoders, Cross-Modal Fusion)* | Modality encoders, projection/adapter bridges, alignment space, fusion/decoder paths | Cross-modal attention support + top-$k$ aligned tokens/patches | Modality dominance/collapse, projection misalignment, grounding shortcut, cross-modal conflict failure | Swap matched modality embeddings, isolate unimodal vs. fused; targeted projection or fusion-path edit | Modality absence/conflict, grounding, retrieval, unimodal regression |
| **12. OCR, Document Structure, ASR, TTS & Audio Codecs** *(CTC, RNN-T, Conformer, Vocoders)* | Visual/acoustic frontend, encoder, blank/repeat CTC/RNN-T logits, alignment/duration predictor, decoder, vocoder | Peak-alignment frame/path hash + blank/non-blank transition mask | Blank/repeat collapse, combining-mark/script drop, encoder vs. decoder prior conflict, duration/prosody drift, vocoder artifacts | Oracle crop/phoneme/duration/alignment stubs (diagnostic only) + encoder/decoder swaps; localized frontend, acoustic, or head repair | CER/WER, per-script/font/digit/currency/table layout F1, speaker-independent intelligibility/naturalness, streaming, silence |
| **13. Reinforcement Learning, World Models & Planners** | Observation encoder, policy $\pi$, value/Q heads, reward/dynamics model, recurrent state | Discrete action/skill ID + state-value margin bucket | Reward hacking/shortcut, policy/value mismatch, world-model rollout drift, unsafe boundary action | Off-policy counterfactual interventions + bounded simulated rollout; constrained policy/value edit | Return distributions, constraint/safety violations, seed & environment shift, exploration |
| **14. Continuous-Time, Implicit & Scientific ML** *(Neural ODE/SDE, DEQ, PINN, Neural Operators)* | Vector-field Jacobian $J_f$, DEQ fixed-point contraction $\|J_g\|$, spectral operator, physics/boundary residual | ODE stiffness/step-size regime; DEQ contraction margin bucket | Drifted equilibrium, local non-contractive zone ($\|J_g\| \ge 1$), stiff blowup, boundary/conservation violation | Perturb vector field/fixed point with solver controls; contraction-preserving Jacobian barrier edit | Solver/step-size sensitivity, convergence, conservation laws, boundary conditions |
| **15. Spiking, Reservoir & Cellular Automata** | Membrane potential, threshold/reset, spike timing, reservoir/readout weights | Spike-time pattern / firing-burst hash | Dead/runaway firing, timing-window drift, unstable reservoir echo state | Controlled impulse/event input; threshold or readout weight edit | Temporal precision, event sparsity, reset behavior, hardware parity |
| **16. Equivariant, Geometric, Capsule & Hyperbolic** | Group-action / tensor representations, routing couplings, manifold metrics | Equivariant invariant-feature / routing hash | Symmetry breaking, manifold numerical drift, collapsed capsule routing | Transform input and verify equivariant output; representation/manifold-preserving constrained edit | Group symmetry (rotations/reflections), manifold validity |
| **17. Hypernetworks, LoRA/Adapters & Ensembles/Neuro-Symbolic** | Conditioning-to-weight map, low-rank adapter factors, module interfaces & symbolic constraints | Active adapter/module branch ID + conditioning cluster | Generator collapse, adapter interference, interface calibration drift, symbolic constraint bypass | Patch generator conditioning vs. generated weights; oracle module stubs; scoped adapter/generator/interface edit | Unseen conditioning, merge/unmerge parity, interface invariants, fallback behavior |
| **18. Non-Neural Learned Models** *(Trees, GBDT, RF, SVM, kNN)* | Split rules, leaf values, support vectors, distance metric, ANN indexes | Leaf-path tuple / active support-vector set | Boundary split drift, outlier leaf, stale/corrupted neighbor index | Feature/rule isolation; constrained leaf/readout edit or reproducible index rebuild | Exact decision parity, calibration, split boundaries |
| **19. Cross-Cutting: Quantized, Binary/Ternary, Pruned & On-Device** | Bit-packing, scale/zero-point/group size, outlier channels, sparsity masks, master float weights | Quantization-bin boundary-proximity mask | Clipping/outlier overflow, dequantization scale drift, kernel fusion mismatch | Float-master vs. deployed-layer counterfactual substitution; repair master/float representation + re-export/requantize (never blindly edit packed bits) | Exact packed format, kernel parity, memory/latency budget, deployment arithmetic |
| **20. Novel / Hybrid Architectures** | Explicit source-equation operator graph | Composed hash of constituent primitive operators | Derive per-operator contract (below); isolate subpaths with oracle stubs | Composed operator interventions with matched controls; mark unsupported mechanisms `inconclusive` | All composed paths, interaction terms, and execution modes |

**Universal Operator Adapter Template (for unseen/novel operators):** Define `operator_id`, equation & tensor axes, data/weight/state inputs, expected invariants, static checks, dynamic summaries, clean/corrupt pairs, safe causal intervention + controls, candidate constrained edit, neighboring dependencies, local metrics, whole-model regression, and unsupported assumptions.

### Domain & Project Task Overlays (Apply Alongside Backbone Adapter)

- **Language & Coding Models (incl. PMM-Coders):** Separate next-token loss, exact recall, algorithmic correctness, instruction following, tool schemas, syntax/compilation, and sandboxed unit tests (bounded resources, no secrets/network). Split by repository/problem family. Audit the serving wrapper (OpenAI/Anthropic-compatible API, tokenization, chat templates, streaming, tool-call parsing, context truncation) separately from model weights.
- **Explicit Recurrent Memory (incl. PMM):** Run a controlled synthetic key/value or code-symbol retrieval audit varying gap, distractors, overwrite rate, and read positions. Compare equal-byte memory-free state, random/recency policy, and oracle addressing under matched data/compute. Patch write value, pre-read state/slot, and copy/read output separately; instrument actual detach points to separate BPTT gradient truncation from representational capacity.
- **OCR, Document & Financial Extraction (incl. FinTech OCR):** Evaluate CER/WER, exact financial fields, geometry/reading order, layout F1, and table cell structure. Isolate Khmer/English scripts, combining marks, digits, currency, stamps, fonts, rotations, low-quality scans, and document-level leakage. Never allow post-correction heuristics to hide degraded raw recognition.
- **Speech & TTS (incl. KhmerTTS):** Use speaker-independent splits; test phoneme/pronunciation coverage, duration alignment, intelligibility, and blinded naturalness. Separate frontend, acoustic model, duration predictor, and vocoder/codec faults.
- **Vision, Generative Media & Safety/Clinical:** Use image/episode-level independent units (not correlated pixels/tokens); use seed-paired metrics + independent seeds for stochastic models; define asymmetric failure costs for clinical/financial/autonomous domains.

---

## 3. Behavioral Baseline & Coverage-Guided Trigger Fuzzing

1. **Parity & no-op controls first:** Confirm exact artifact loading and reference forward parity (shapes, masks, tensor layout, state reset, batch vs. streaming, deterministic settings). Run a no-op hook/edit control. If parity fails, resolve the implementation/runtime discrepancy before inspecting weights.
2. **Encode the executable oracle:** Implement `proto(raw_input)` returning authoritative decisions plus per-rule active flags and explicit boundary-tolerance masks (`keep`).
3. **Stratified & targeted pools:** Build a broad baseline pool over valid input domains plus targeted pools for rare rules, missing-feature flags, long horizons, extreme graph degrees, or rare routing combinations. Keep ambiguous samples labeled separately.
4. **Coverage-guided activation-hash trigger fuzzing:** Uniform pools rarely hit exponentially narrow trigger boxes. Using the architecture's fast **Region Hash** $h(x)$ (from the Matrix), run a coverage-guided differential fuzzer seeded from the stratified pool:
   - Apply protocol-valid mutations (continuous perturbations, patch swaps, token/motif edits, temporal shifts).
   - Prioritize mutations that unlock an unseen region hash $h(x)$ or shrink the margin between network decision and protocol flip while sibling rules remain inactive.
   - Promote discovered disagreement clusters to candidate claims—never treat raw fuzzer hits as confirmed before Step 5.
5. **Triage non-weight causes first:** Measure overall and per-slice error, cluster failures by input features and region hash, and rule out preprocessing, tokenization, label, loss, decoding, or serving-wrapper bugs before blaming weights. Treat trigger/backdoor hunting strictly as defensive auditing; never implant bypasses or publish operational exploit recipes.

---

## 4. Coarse-to-Fine Localization & Causal Verification

Localize progressively (`subsystem -> layer/block -> path -> channel/head/expert/state subspace -> parameter slice`) using four ordered passes:

- **4A. SSA Graph Lowering & Backward Def-Use Slicing:** Lower the model into SSA primitives and slice backward from the decision logit/output to prune operators disconnected from the suspect rule's inputs.
- **4B. Static Integrity & Dynamic Sparsity / Dead-Subspace Audit:** Inspect tensor finiteness, aliasing, norms, singular spectra, quantization clipping, activation quantiles, gate occupancy, routing loads, and read/write utilization. Near-inactive components (e.g., active <3% of inputs, collapsed heads/experts, dead VQ codes) flag both **silenced rules** and **free surgical capacity**. Static magnitudes alone are never causal proof.
- **4C. Native Spectral, Pole-Zero & Matched-Filter Diagnostics:** Inspect sliced operators in their canonical basis:
  - *MLPs/KANs:* Effective switch-on hyperplanes $-b/w$ in physical units or local spline-knot offsets.
  - *CNNs/GNNs:* FFT frequency response or graph-Laplacian eigenspectrum against protocol feature templates.
  - *Transformers:* Bilinear $W_Q^\top W_K$ attention score spectrum, RoPE phase bands, and $W_O W_V$ logit-write alignment.
  - *RNNs/SSMs/DEQs/ODEs:* Linearized eigenvalues/poles $\lambda_i$, Hankel singular values, and spectral radius $\rho(A)$ in both float64 and target quantized precision (catching $\rho(A_{\text{quant}}) \ge 1$ blowup before rollout).
- **4D. Paired Causal Interventions & Fault-Tree Minimal Cut Sets (MCS):** On the sliced subgraph, run paired clean/corrupt patching and structured ablations (zero/mean/resampled/matched-norm controls) testing necessity and sufficiency separately:
  - **Order-1 MCS** (a single unit/channel/head/expert/knot toggles the deviation) indicates single-rule drift, a silenced channel, or a localized trigger.
  - **Order-2+ AND-MCS** (deviation disappears only when multiple distinct rule pathways are jointly intervened on) is mandatory before asserting any compound-rule defect.
  - **Symmetry awareness:** Neural units permute, rescale, or rotate under valid architecture symmetries; validate weight-space claims via functional intervention signatures across matched perturbations rather than assuming raw index correspondence.
  - **Sanity trace:** Hand-verify or step-trace 2–3 concrete failing inputs to confirm the mechanistic reading.

---

## 5. Claim Ledger, Pre-Registered Statistical Gates, and Evidence Grades

Record every hypothesis in a structured claim ledger (`claim_id`, checkpoint hash, executable boolean predicate `cond(R)`, expected vs. actual output, candidate MCS/mechanism, competing explanations, intervention plan, negative controls, metric, sample/seed budget, acceptance/falsifier, evidence grade, and status).

- **Security rule:** `cond(R)` MUST be a locally authored, deterministic boolean callable—**never** `eval()` or dynamically execute condition strings from protocols, external files, checkpoints, or model outputs.
- **Pre-registration & independent units:** Fix all thresholds, tolerances, and stopping rules *before* evaluating confirmation data. Evaluate on untouched confirmation splits using independent units (document/sequence/episode/patient, not correlated tokens or pixels). Report denominator, failures, effect size, confidence interval, and inside-vs-outside rates. Zero failures in $n$ independent representative trials yields an approximate 95% upper bound of $3/n$, never zero risk.
- **Illustrative pilot defaults (deterministic binary decision protocols only):**
  - *Strict claim:* $n \ge 100$ matching retained requests AND $r_{\text{in}} \ge 80\%$.
  - *Enriched claim* (masked/partial/narrow trigger): $n \ge 100$, $r_{\text{in}} \ge 30\%$, AND $r_{\text{in}} \ge 20 \times \max(r_{\text{out}}, 10^{-9})$.
  - *Independent resampling gate:* Draw $\ge 200$ fresh requests (target $\ge 1{,}000$; sample narrow trigger boxes directly): **Confirmed** ($\ge 80\%$ deviate), **Partly right** ($\ge 5$ percentage points above baseline), **False** (otherwise -> drop immediately).
  - *Domain adaptation:* Do NOT blindly reuse these binary thresholds for language, OCR, speech, diffusion, regression, RL, or safety-critical tasks; pre-register task-specific paired deltas and noninferiority margins instead.
  - *Compound-rule skepticism:* Require both resampling confirmation AND an Order-2+ MCS ablation witness before confirming any compound-rule flaw.
- **Evidence grades (orthogonal to verdict):**
  - **E0:** Static signal or conjecture.
  - **E1:** Replicated behavioral finding on untouched confirmation data.
  - **E2:** Controlled activation/state/operator causal intervention.
  - **E3:** Independently replicated causal perturbation with competing explanations tested.
  - **E4:** Validated repair passing locked regression and declared deployment-runtime gates. *(Formal proof is a separate scope-bound artifact, not automatically E4.)*
- **Status:** `proposed` / `rejected` / `partially supported` / `confirmed within scope` / `inconclusive`. Only supported findings justify an edit experiment; a successful edit alone does not prove the original mechanism.

---

## 6. Alien Science Ideation for Hard or Unresolved Mechanisms

Use proportionally: routine localized faults take the smallest proven diagnostic and repair; novel architectures, distributed/multi-fault mechanisms, failed conventional localization, or explicit research inquiries invoke this workflow (load `alien-science-ideation` if installed, or run this fallback):

1. **Atomize** the bottleneck into 6–10 core operational mechanisms (e.g., QK routing, OV transport, state decay, slot addressing, CTC blank dynamics, quantizer clipping, expert capacity, gradient truncation) and 6–10 boundary atoms from outside ML (compiler SSA slicing, aerospace fault-tree MCS, control observability/CBF, tropical polytope hashing, radar matched filters, error-correcting syndromes, metamorphic replay, abstract interpretation).
2. **Recombine** into 8–12 candidate bridges (2–4 atoms each, roughly half cross-disciplinary), always including conventional baselines and a null explanation (data/wrapper/runtime artifact).
3. **Score independently** on Coherence $C \in [1,5]$, Estimated Availability $A \in [1,5]$ ($5=$ obvious), Feasibility $F \in [1,5]$, and Verification Leverage $V \in [1,5]$. Do not average away low coherence. Target frontier: $C \ge 4, A \le 2$, feasible and falsifiable. *(Scores are qualitative heuristics, not empirical proof or novelty claims.)*
4. **Select 1–5 diverse falsifiable sketches**, each with hypothesis, competing explanations, minimal toy/small-checkpoint experiment, matched budget/control, falsifier, failure modes, and rollback. Run the cheapest discriminating test first; Vera checks coherence and baseline fairness. Never promote an untested sketch into a production repair.

### Alien Frontier Mechanism Catalog (Falsifiable Engineering Hypotheses)

| Mechanism | Atom Bridge | Target Bottleneck |
| :--- | :--- | :--- |
| **SSA Slicing + Fault-Tree MCS** | Compiler def-use slicing + aerospace minimal cut sets | Separating genuine compound-rule defects from masked single-rule faults in arbitrary graphs |
| **Activation-Hash Trigger Fuzzing** | Tropical polytope/routing region hashes + coverage-guided differential fuzzing | Discovering exponentially narrow trigger windows where uniform sampling fails |
| **Spectral & Pole-Zero Operator Audit** | Control pole-zero/Hankel analysis + matched-filter deconvolution + quantized radius | Localizing filter/temporal drift and predicting fp16/int8 rollout blowup before execution |
| **Barrier-Certified Null-Space Surgery** | Null-space projected edits + discrete Control Barrier Function (CBF) | Repairing deep/stateful/diffusion/DEQ models without collateral flips or rollout divergence |
| **Localized Subgraph IBP Witnessing** | SSA subgraph slicing + interval/zonotope bounds + rounding intervals | Producing bounded local non-overflow and non-regression certificates without whole-net explosion |
| **State Reach/Read Tomography** | Gated recurrence + control observability + causal state patching | Diagnosing silent memory decay, unreachable slots, and read/write decoupling in SSMs/PMMs |
| **Parameterization-Invariant Signatures** | Group symmetries + causal mediation + differential testing | Localizing mechanisms robustly across weight permutations/rescalings and checkpoint comparisons |
| **Syndrome-Guided Multi-Fault Localization** | Fault injection + error-correcting syndromes + operator interventions | Disentangling co-occurring interacting faults with minimal forward-pass budget |
| **Precision-Boundary Counterfactual Replay** | Quantization bins + metamorphic replay + layerwise high-precision substitution | Pinpointing exact layers causing float-to-quantized decision flips |
| **Temporal Gradient-Reach Assay** | Detach-point instrumentation + controlled impulse + delayed retrieval | Separating BPTT truncation bugs from representational memory limits |
| **Cross-Modal Oracle Triangulation** | Causal mediation + modular boundary substitution + differential oracle | Isolating encoder vs. adapter vs. fusion vs. decoder failures in VLMs/OCR/TTS |
| **Alignment Topology Tomography** | CTC/RNN-T blank dynamics + constrained forward-backward path counterfactuals | Separating alignment/blank collapse from visual/acoustic encoder failure (OCR/ASR) |
| **Router Conservation Audit** | Conditional MoE experts + flow conservation + counterfactual routing | Detecting expert starvation, token-drop drift, and adversarial routing flips |

---

## 7. Minimal Repair Ladder and Weight-Space Programming

Diagnose before repairing. Always compare at least: (a) unchanged checkpoint, (b) an appropriate conventional repair (fine-tuning, LoRA, preprocessing/wrapper/decoder fix), and (c) the proposed minimal weight edit. If the fault lives in preprocessing, tokenization, decoding, retrieval, or serving wrappers, fix that layer rather than weights.

1. **Level 1 — Exact analytical circuit edit:** Shift biases, folded kernel gains, pole positions, or local KAN spline knots on verified Order-1 MCS operators; repurpose dead units/channels/heads/experts and zero stray connections. Preserve tied weights and structural constraints.
2. **Level 2 — Null-space & barrier-certified sparse/low-rank edit:**
   - *Null-space projection:* On dense layers, collect retained-correct activation covariance $C_{\text{keep}} = H_{\text{keep}}^\top H_{\text{keep}}$ and project $\Delta W$ into its damped orthogonal complement $P_\perp = I - C_{\text{keep}}(C_{\text{keep}} + \lambda I)^{-1}$ to suppress single-step collateral regressions. (For rank-1 updates $\Delta W = (v - W k)k^\top / (k^\top k)$, verify exact bias, norm, dtype, orientation, and retained directions—never treat raw rank-1 edits as a universal recipe.)
   - *Control-Barrier constraint (stateful/iterative models):* For RNNs, SSMs, multi-hop GNNs, Diffusion/Flow, and DEQs, enforce a discrete Control Barrier Function check $B(h_{t+1}) \ge (1-\alpha)B(h_t)$ and spectral contraction $\rho(A_{\text{edited}}) < 1$ (where stability is required) over $2\times$–$5\times$ rollout horizons.
   - *Magnitude discipline:* Avoid extreme weights (e.g., $\ge 10^4$ in fp16 or near quantization clip limits); rescale smoothly instead.
3. **Level 3 — Constrained local optimization / adapters vs. full fine-tuning:** Optimize localized parameters or LoRA on the `repair` split only with explicit preservation loss; quantify rank, affected modules, norm, parameter count, serialized bytes, and latency. Never privilege small parameter count over behavioral safety.
4. **Level 4 — State, routing, and quantized models:** For stateful/memory systems, test reset, initialization, addressing, and runtime controls first—distinguish state changes from weight edits. For quantized/binary/ternary models, repair the supported float master representation (or documented native format) and re-export/requantize; never mutate packed bits without format semantics.
5. **Edit Manifest (authorized copies only):** Record tensor name, logical index/slice or low-rank factors, old/new SHA-256, dtype, operation, rationale, tied aliases, seed, bounds, and rollback procedure. Verify shape/layout, finiteness, immutable base hash, serialized size, and clean reload.

**Optional — Author a protocol-compliant subnetwork from scratch:** Where representable (threshold logic, ReLU min/max gadgets, exact KAN splines, finite-state SSM integrators, explicit QK/OV matchers), construct weights from an executable spec and validate on broad/stratified pools, held-out boundary windows, coverage-guided trigger fuzzing, and deployment precision. Label composition into large trained models as experimental.

---

## 8. Regression, Localized Witnessing, and Deployment Verification

Never recommend an edit until all four gates pass on a **copy** of the weights:

1. **Paired locked-set regression:** Evaluate target efficacy (e.g., $\le 5\%$ error in verified binary claim region, or pre-registered noninferiority margin for continuous/generative tasks), paraphrase/compositional generalization, collateral damage (`broke`: previously correct -> wrong vs. `fixed`), worst-slice performance (never means alone), extended stress pools (scale up to $10^6$–$2\times 10^7$ requests where compute permits + $2\times$–$5\times$ rollouts for stateful/generative models), and a **fresh post-edit fuzzing pass** to confirm no new trigger was introduced. If further training is planned, test repair retention over a bounded matched training continuation.
2. **Localized Abstract-Interpretation Witness:** Propagate interval or zonotope bounds *strictly through the SSA-sliced edited subgraph* using empirical input/activation envelopes from the retained pool plus deployment rounding margins $[-\epsilon_{\text{dtype}}, +\epsilon_{\text{dtype}}]$. Record exact domain, solver status (`WITNESSED` / `LOOSE` / `UNKNOWN`), and unsupported operators. A timeout is `UNKNOWN`, never a pass.
3. **Actual deployment arithmetic & runtime verification:** Reproduce in the real target runtime and quantization (fp16, bf16, fp8, int8/int4, ONNX Runtime, TensorRT, vLLM, MCU) across realistic batch sizes, sequence lengths, caches, streaming modes, and kernel fusions. Check **weights, every intermediate tensor, and final outputs** for unexpected `NaN`/`Inf`/saturation (nonlinearities like ReLU or clipping can hide `-Inf` intermediates; distinguish legitimate masking sentinels such as `-Inf` in attention masks and verify they appear *only* in intended masked positions). Remember fp16 max finite magnitude is 65,504. If the real runtime is unavailable, run a dtype proxy *and* explicitly report **`Deployment Runtime Verification: NOT RUN`**.
4. **Stop/revert & re-commissioning:** Immediately revert on any pre-registered gate failure, unexpected non-finite value, unacceptable collateral regression, or runtime mismatch. Treat any weight edit as a substantive change requiring full re-commissioning by qualified reviewers; never issue clinical, financial, or regulatory sign-off from an audit alone.

---

## Architecture-Agnostic Reference Toolkit (PyTorch + NumPy)

Adapt `region_hash` and `mutate_fn` to your modality. For the original two-hidden-layer NumPy ReLU helper, see `references/relu-audit.md` if present.

```python
import copy
import numpy as np
import torch
import torch.nn as nn

# 1. Architecture-Agnostic Hook Recorder (Activations + Non-Finite Detection)
class AuditProbe:
    """Attach to SSA-sliced modules of any PyTorch architecture to capture
    intermediate tensors, region hashes, and low-precision overflow checks."""
    def __init__(self, model: nn.Module, module_names: list[str],
                 allow_neg_inf_modules: set[str] | None = None):
        self.model = model
        self.captures = {}
        self.nonfinite_counts = {}
        self.allow_neg_inf_modules = allow_neg_inf_modules or set()
        self._handles = []
        named = dict(model.named_modules())
        for name in module_names:
            self._handles.append(named[name].register_forward_hook(self._make_hook(name)))

    def _make_hook(self, name):
        def hook(_mod, _inp, out):
            t = out[0] if isinstance(out, (tuple, list)) else out
            if torch.is_tensor(t):
                self.captures[name] = t.detach()
                if name in self.allow_neg_inf_modules:
                    bad = torch.isnan(t) | torch.isposinf(t)
                else:
                    bad = ~torch.isfinite(t)
                self.nonfinite_counts[name] = int(bad.sum().item())
        return hook

    def region_hash(self, quantile_buckets: bool = False) -> list[bytes]:
        """Per-sample discrete activation/routing hash across probed layers."""
        sigs = []
        for name in sorted(self.captures):
            t = self.captures[name]
            flat = t.reshape(t.shape[0], -1)
            if quantile_buckets:
                bins = torch.tensor([-1.0, 0.0, 1.0], device=flat.device, dtype=flat.dtype)
                code = torch.bucketize(flat, bins).to(torch.uint8)
            else:
                code = (flat > 0).to(torch.uint8)
            sigs.append(code.cpu().numpy())
        joined = np.concatenate(sigs, axis=1)
        return [row.tobytes() for row in joined]

    def close(self):
        for h in self._handles:
            h.remove()

# 2. Coverage-Guided Activation-Hash Trigger Fuzzer
@torch.no_grad()
def fuzz_triggers(model, probe, seed_X, proto_fn, decision_fn, mutate_fn,
                  steps=500, batch_size=256):
    """Hunt narrow trigger regions by rewarding unseen region hashes."""
    seen_hashes = set()
    frontier = [seed_X[i] for i in range(min(len(seed_X), 1024))]
    disagreements = []
    for _ in range(steps):
        idx = np.random.randint(0, len(frontier), size=batch_size)
        batch = torch.stack([mutate_fn(frontier[i]) for i in idx])
        logits = model(batch)
        hashes = probe.region_hash()
        net_dec = decision_fn(logits)
        pro_dec = proto_fn(batch)
        for i in range(batch_size):
            if net_dec[i] != pro_dec[i]:
                disagreements.append(batch[i].cpu())
            if hashes[i] not in seen_hashes:
                seen_hashes.add(hashes[i])
                frontier.append(batch[i].cpu())
    return disagreements, len(seen_hashes)

# 3. Pre-Registered Claim Verification (Safe Locally Authored Callable Only)
def verify_claim(cond, R, net, proto, keep, kind="strict"):
    """Verify a locally authored boolean callable against fixed thresholds.
    Never eval() condition strings from protocols, files, or model outputs."""
    if not callable(cond) or kind not in ("strict", "enriched"):
        raise ValueError("Expected a callable condition and kind in {'strict','enriched'}")
    raw = np.asarray(cond(R))
    keep = np.asarray(keep, dtype=bool)
    if raw.dtype != np.bool_ or raw.shape != keep.shape:
        raise ValueError("Claim callable must return a boolean mask matching keep")
    m = raw & keep
    dev = np.asarray(net) != np.asarray(proto)
    n = int(m.sum())
    r_in = float(dev[m].mean()) if n else float("nan")
    outside = (~m) & keep
    r_out = float(dev[outside].mean()) if outside.any() else float("nan")
    if kind == "strict":
        ok = (n >= 100) and (r_in >= 0.80)
    else:
        ok = (n >= 100) and outside.any() and (r_in >= 0.30) and (r_in >= 20.0 * max(r_out, 1e-9))
    return dict(n=n, rate_in=r_in, rate_outside=r_out, confirmed=bool(ok))

# 4. Null-Space Projected Weight Edit
@torch.no_grad()
def project_null_space_delta(delta_W: torch.Tensor, H_keep: torch.Tensor, damping: float = 1e-3):
    """Project weight update delta_W (out_dim, in_dim) into the damped null
    space of retained-correct layer inputs H_keep (N, in_dim)."""
    H = H_keep.to(torch.float64)
    cov = (H.T @ H) / max(H.shape[0], 1)
    eye = torch.eye(cov.shape[0], dtype=torch.float64, device=cov.device)
    proj = eye - cov @ torch.linalg.solve(cov + damping * eye, eye)
    return (delta_W.to(torch.float64) @ proj).to(delta_W.dtype)

# 5. Deployment-Precision Proxy + Intermediate Non-Finite Check + Local IBP Witness
@torch.no_grad()
def deployment_numerics_check(model: nn.Module, X: torch.Tensor, keep_mask: np.ndarray,
                              decision_fn, probed_modules: list[str],
                              target_dtype=torch.float16,
                              allow_neg_inf_modules: set[str] | None = None):
    """Dtype proxy check inspecting weights, intermediate activations, and outputs.
    Not a substitute for real target-runtime verification."""
    keep = np.asarray(keep_mask, dtype=bool)
    m_fp64 = copy.deepcopy(model).to(torch.float64).eval()
    m_low = copy.deepcopy(model).to(target_dtype).eval()
    probe_low = AuditProbe(m_low, probed_modules, allow_neg_inf_modules=allow_neg_inf_modules)
    try:
        out64 = m_fp64(X.to(torch.float64))
        out_low = m_low(X.to(target_dtype))
        inter_nonfinite = sum(probe_low.nonfinite_counts.values())
    finally:
        probe_low.close()
    nonfinite_weights = sum(int((~torch.isfinite(p)).sum().item()) for p in m_low.parameters())
    max_abs_weight = max(float(p.abs().max().item()) for p in m_fp64.parameters())
    nonfinite_out_low = int((~torch.isfinite(out_low)).sum().item())
    nonfinite_out_64 = int((~torch.isfinite(out64)).sum().item())
    mismatch = int((np.asarray(decision_fn(out64))[keep] != np.asarray(decision_fn(out_low))[keep]).sum())
    passed = (nonfinite_weights == 0 and inter_nonfinite == 0
              and nonfinite_out_low == 0 and nonfinite_out_64 == 0 and mismatch == 0)
    return dict(passed=passed, max_abs_weight=max_abs_weight,
                nonfinite_weights=nonfinite_weights, nonfinite_intermediate=inter_nonfinite,
                nonfinite_out_low=nonfinite_out_low, nonfinite_out_64=nonfinite_out_64,
                mismatch_vs_fp64=mismatch,
                runtime_note="PyTorch dtype proxy; report Deployment Runtime Verification: NOT RUN unless tested on target runtime")

@torch.no_grad()
def interval_linear_witness(W: torch.Tensor, b: torch.Tensor,
                            x_lo: torch.Tensor, x_hi: torch.Tensor,
                            rounding_eps: float = 1e-3):
    """Exact interval bound propagation (IBP) through a sliced linear operator
    with deployment-precision rounding margin."""
    W_pos = torch.clamp(W, min=0)
    W_neg = torch.clamp(W, max=0)
    y_lo = x_lo @ W_pos.T + x_hi @ W_neg.T + b - rounding_eps
    y_hi = x_hi @ W_pos.T + x_lo @ W_neg.T + b + rounding_eps
    return y_lo, y_hi
```

---

## Rules That Matter

- **Never treat `follows` as clearance.** Finite-pool passes, fuzzing budgets, spectral reads, or localized interval witnesses are bounded evidence, never global proof. State every untested boundary explicitly.
- **Never force a verdict.** When budget or evidence is insufficient, return `inconclusive` and specify the cheapest next discriminating test.
- **Only verified claims reach the edit list.** Unverified, failed-resampling, or unablated compound-rule claims are logged as rejected and never edited.
- **Fix thresholds before viewing confirmation results.** No post-hoc threshold tuning or deadband shifting.
- **Never trust a float64-only repair.** Always test collateral damage, extended rollouts (if stateful/generative), post-edit fuzzing, localized bounds, and target deployment arithmetic including intermediate tensors.
- **Keep baselines in view.** Always weigh minimal weight edits against protocol-labelled fine-tuning/LoRA, non-weight (wrapper/decoder/data) fixes, and formal verifiers ($\alpha,\beta$-CROWN, Marabou).
- **Re-commission after any repair.** Audit outputs are decision aids for qualified reviewers, never autonomous safety or regulatory sign-off.

---

## Output Contract

Return concise findings proportional to scope (and when executing a substantial audit, save `audit-manifest.json`, `claims.jsonl`, `metrics.json`, `edits.json`, `verification.json`, and `report.md` in an authorized directory without dumping sensitive raw data):

1. **Verdict & Evidence Grade:** `follows` / `deviates` / `inconclusive`, Evidence Grade (`E0`–`E4`), architecture family, access tier (`A0`–`A4`), deployment target, and scope/unknowns.
2. **Baseline Metrics & Operator Graph:** Reference parity status, SSA slice summary, dead/silenced components, spectral/pole-zero anomalies, and fuzzing coverage (unique region hashes explored).
3. **Verified Claim Ledger:** Claim ID, predicate, expected vs. actual output, sample size, CI, inside-vs-outside deviation rates, resampling outcome, and Fault-Tree MCS order/operators.
4. **Rejected / Inconclusive Hypotheses & Alien Sketches:** Why each failed (resampling, sibling-rule masking, failed Order-2+ MCS ablation) plus any Alien Frontier tests run.
5. **Candidate Repair Manifest & Baselines:** `(param, index/slice or rank-k factors, old/new hash, constraint applied)`, null-space/CBF details, rollback plan, and baseline comparison.
6. **Verification & Witness Matrix (`PASS` / `FAIL` / `NOT RUN`):** Target efficacy, collateral `broke` vs. `fixed` (locked + stress + extended rollout), post-edit fuzzing, localized IBP/zonotope witness status, deployment arithmetic (intermediate non-finites, max $|\text{weight}|$, runtime parity), and training-retention check if applicable.
7. **Unresolved Risks & Next Discriminating Test:** Untested subdomains, trigger-size lower bounds, approximation gaps, and the cheapest next experiment.

---

## Optional Reference Routing (Multi-File Skill Package)

When installed as a multi-file skill directory, pair this `SKILL.md` with:
- `references/architecture-playbook.md` — extended operator adapters and task overlays.
- `references/alien-experiments.md` — falsifiable Alien Frontier experiment designs and controls.
- `references/relu-audit.md` — original Nusrat & Nusrat small-ReLU workflow and NumPy helper.
- `references/research.md` — primary citations and evidence-scope boundaries.
