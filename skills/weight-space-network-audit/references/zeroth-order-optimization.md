# Zeroth-order optimization and per-sample clipping

Applies to the Level 3 search claw of the parent skill, and only when the user explicitly asked for the broader universal method. Default Quintet work stays on `relu-audit.md`.

Primary source: [Understanding Clipping In Zeroth-Order Optimization (arXiv:2611.33062)](https://arxiv.org/abs/2611.33062), code [github.com/SewoongLab/ClipZero](https://github.com/SewoongLab/ClipZero) (`roberta/src/trainer.py:135,251-270,511-600`). Estimator details below are transcribed from that paper (Eqs. 1-2) and code. Everything the paper does not measure is marked as our own obligation, not theirs.

## Estimator and clipping

Per step, per tensor: one Gaussian direction, shared across the whole batch, regenerated from a stored seed. The absolute step size is `eps`; it is **not** scaled by `||theta||`. The directional derivative is formed per example from two forward passes, clamped per example as a scalar, then averaged, then multiplied by the direction.

```python
import torch

def zo_clipped_step(model, master, batch, eps=1e-3, c=5.0, lr=1.0e-4, seed=0):
    """Two-forward ZO step with per-sample scalar clipping (arXiv:2611.33062, Eqs. 1-2).

    master: name -> fp32 parameter tensors (the perturbation targets). Never bf16/fp16.
    """
    gen = torch.Generator(device="cpu").manual_seed(seed)          # z is regenerated, not stored
    z = {n: torch.randn(t.shape, generator=gen, dtype=torch.float32) for n, t in master.items()}

    def shift(sign):                                               # theta <- theta + sign*eps*z
        with torch.no_grad():
            for n, t in master.items():
                t.add_(z[n], alpha=sign * eps)

    with torch.no_grad():
        shift(+1)
    l_plus = per_example_loss(model, batch)                        # reduction='none' -> shape [B]
    with torch.no_grad():
        shift(-2)                                                  # back through theta to theta - eps*z
    l_minus = per_example_loss(model, batch)
    with torch.no_grad():
        shift(+1)                                                  # restore theta

    delta = ((l_plus - l_minus) / (2 * eps)).clamp(-c, c)          # clamp the SCALAR, per example
    g = delta.mean()                                               # one scalar for all coordinates
    with torch.no_grad():
        for n, t in master.items():
            t.sub_(z[n], alpha=lr * float(g))                      # no 1/d, no 1/sqrt(d)
    return float(g)
```

Clipping placement is load-bearing: clamp each example's scalar **before** aggregation and **before** multiplying by `z`. What makes a *different* estimator is where the clamp sits relative to the **aggregation**: clamping the **aggregate** (batch-mean scalar, or the summed update) instead of each example is a different estimator and is the control arm. Clipping after the `z` multiply is **not** a different method: for a direction shared across the batch, clipping each example's `delta_i*z` to a norm bound is a reparameterisation of per-sample scalar clipping at `c/\|z\|` (measured agreement: max abs diff `8.33e-17` at `c = 5.0`, `\|z\| = 70.370562`, `artifacts/gate_tests.json/postz_algebra`), so implement whichever is convenient and never report the two as different arms.

Two mechanical conditions on the block above, both silently fatal if missed:

- `master` must alias the tensors the forward pass actually reads (re-point each parameter's `data`, or run the model from the master). Perturbing a detached clone leaves `l_plus == l_minus` for every example, so every `delta_i` is zero and `g` is zero with no error.
- `theta + eps*z` then `theta - 2 eps*z` then `theta + eps*z` is not bit-exact in fp32; the residue is a few ULPs of `|theta|` per step and accumulates over an arm. Either perturb per-forward copies and leave the master untouched, or measure and record the residue so the arm's start point is known.

Liveness must be asserted, once per arm, before any result is trusted:

```python
def assert_perturbation_live(master, storage_dtype, eps, tol_rel=1e-3, gen=None):
    """Fail if theta +/- eps*z collapses to the same stored tensors."""
    gen = gen or torch.Generator().manual_seed(0)
    z = {n: torch.randn(t.shape, generator=gen, dtype=torch.float32) for n, t in master.items()}
    plus = {n: (t + eps * z[n]).to(storage_dtype).float() for n, t in master.items()}
    minus = {n: (t - eps * z[n]).to(storage_dtype).float() for n, t in master.items()}
    got = torch.linalg.vector_norm(torch.cat([(plus[n] - minus[n]).flatten() for n in master]))
    want = 2 * eps * torch.linalg.vector_norm(torch.cat([z[n].flatten() for n in master]))
    assert torch.isfinite(got) and abs(got - want) <= tol_rel * want, (float(got), float(want))
```

## Defaults and their scope

| Knob | Paper setting | Scope caveat |
| :--- | :--- | :--- |
| Direction `z` | $z \sim N(0,I)$ per tensor, one per step, shared across the batch, redrawn each step from a stored seed | Storing the seed instead of `z` is what keeps memory at parameters + one regenerated tensor. |
| `eps` | `1e-3`, absolute | Not `eps*\|\|theta\|\|`. Absolute `eps` on large weights is where the dtype rounding trap lives (below). |
| `c` | Swept `[1, 500]` plus infinity; best reported point `c = 5` on RoBERTa-large | Sweep `c` per backbone; do not copy `5`. |
| `lr` | Swept `[5e-7, 1e-4]`; best reported point gives `lr*c = 5e-4` on RoBERTa-large | The OPT-1.3B `lr*c` figure is **not verified** and is not quoted here. The product is stable only inside the clipping-dominated regime and only per backbone; it is not a universal constant. |
| Optimizer | SGD, constant `lr`, weight decay 0, 10k steps, batch 64 | Paper budget. A bounded pilot uses far fewer steps (parent skill §1.4) and must say so. |
| Model scope | RoBERTa-large (355M) and OPT-1.3B, prompt-based classification (SNLI-style) | No vision, SSM, or decoder-generation results. |

Reported outcomes in that scope: **+1.70 to +2.04 points on SNLI**, a +5.6 point advantage under 30% label flips that vanishes beyond ~50% flips, and calibration degradation that the paper reports as a **figure** rather than a per-arm table — the ~0.12 ECE endpoint belongs to the **unclipped** model under label noise, so no clipped-versus-unclipped ECE delta is quotable from it. Treat these as claims to reproduce, not as priors for a different backbone.

## Three implementation gotchas

1. **bf16/fp16 master weights silently kill the arm.** With `eps = 1e-3` and low-precision storage, `theta + eps*z` can round to `theta`. bf16 has 7 explicit mantissa bits, so its ULP is `2^(floor(log2|theta|) - 7)`: about `9.8e-4` at `|theta| = 0.125` (already the same order as `eps`) and `2e-3 = 2*eps` at `|theta| = 0.25`, where a typical perturbation rounds back to `theta`. Treat `|theta| >= 0.125` as unsafe in bf16; fp16 reaches `eps` near `|theta| = 1`. Run all perturbation arithmetic on an fp32 master copy of the perturbed tensors, keep the stored/deployed dtype for the forward pass if that is the deployment arithmetic, and gate the arm on the liveness assertion above. An fp32 master fixes the *arithmetic*, not the *storage*: the realized direction written into bf16 is still quantized. Measured on the pilot checkpoint in `## Local pilot evidence` (`artifacts/calibration.json/probe`), the fraction of perturbation entries lost to bf16 storage at `eps = 1e-3` was **99.609%** for `global:final_norm` (field `frac_entries_perturbation_lost` 0.99609; cos(realized, intended) = 0.125), **3.468%** for the tied `lm_head`/embedding (0.03468; cos 0.9995), and **2.072%** for `early:linattn_o`, the 12,582,912-parameter ZO subset (0.020720 in the probe, 0.020677 at step 0 of an arm; cos 0.9998). Across the 62 candidate groups the loss spans 0.01347-0.99609 (`layer14:mlp_down` to `global:final_norm`); do not quote it as 1.35%-3.47%, because `global:final_norm` is one of the groups. Where those entries are lost, the per-example loss difference is zero and clipping or unclipping is irrelevant. So assert on the *realized* perturbation, not the intended one.
2. **Clip placement, and what is genuinely a different estimator.** Per-sample scalar clamp before aggregation and before the `z` multiply reproduces the gain. Every implementation that is *not* that method clamps the **aggregate** rather than each example — the batch-mean scalar, or the summed update. Clipping each example's `delta_i*z` to a norm bound after the multiply **is** the same estimator for a shared `z` (it equals per-sample scalar clipping at `c/\|z\|`; measured max abs diff `8.33e-17`, `artifacts/gate_tests.json/postz_algebra`), so it is a reparameterisation, not a control. If your implementation can only clamp the aggregate, the arm is not the paper's method and must not be labelled as such.
3. **No `1/d`, but the step norm grows with dimension.** The update is `theta -= lr * g * z` with a unit-variance `z`, so `||lr * g * z||_2 ~ lr * |g| * sqrt(d)` for `d` perturbed coordinates. `lr` therefore has to fall as the perturbed parameter count grows; only the `lr*c` product is roughly stable, and only while clipping dominates. Any cross-size `lr` comparison that ignores this is measuring step size, not the method.

## Component-restricted ZO

Full-tensor ZO spends its budget spreading a single scalar `g` over every coordinate. Localizing first buys precision and costs search coverage:

1. **Sensitivity probe (forward-only).** For each candidate tensor group (attn `W_Q`/`W_K`/`W_O`/`W_V`, MLP `g`/`u`/`w`, per-layer blocks), take a few stored directions and measure the mean absolute per-example response `|delta_i|` on the `repair` split. Charge every probe forward pass to the arm's examples-seen budget.
2. **Rank and cut.** Rank groups by response per parameter, keep the top groups under a parameter budget, and record the cut line and the discarded groups in the manifest.
3. **Perturb only the selected tensors.** `z` stays unit-variance on the selected support; the effective `d` drops, so the per-step parameter move drops and `lr` can rise; re-tune `lr`/`c` on `calibration` rather than reusing full-tensor values.

Why this changes the variance/precision trade: the estimate is a single random-direction projection, so its error scales with the number of coordinates sharing one scalar and with the norm of the true gradient on the perturbed support. Restricting `d` lowers the per-step noise floor and the step norm at fixed `lr` (better signal per unit of parameter movement), and it also lowers the reachable set: a repair whose direction lies outside the selected groups is unreachable no matter how long the arm runs. Probe passes are usually the dominant cost of the whole arm, so the ranked-subset arm must be compared against a full-parameter arm at the **same total** examples seen, and against a random subset of the same size to show the ranking itself carried information.

Note that the paper reports **no** component-restricted vs full-parameter comparison. Any claim that restriction helps is ours to measure, with the arms above.

## Memory accounting

- **ZO arm:** parameters (storage dtype) + an fp32 master copy of the perturbed tensors (4 bytes/param for those) + `z`. Regenerate `z` per tensor from the stored seed so the peak `z` residency is one tensor rather than the whole model. No activations are retained: the two forward passes are sequential inside `torch.no_grad()`.
- **Backprop/LoRA arm:** the same parameters plus activations `batch x seq x width` per layer held for the backward pass, plus optimizer state for the trainable subset.
- The claim "ZO fits where backprop does not" is a memory claim, so report measured peak RSS (or device memory) per arm at the same batch; a theoretical parameter count is not a measurement. The paper supplies **no** cost, memory, or wall-clock numbers, so any cost table in a report is our own measurement and must be labelled as such.

## Label-noise protocol

Only when robustness is the claim:

1. Freeze the split, then flip a stated fraction of **training** labels (the paper's reported setting is 30%) with a recorded seed; keep the locked test set clean.
2. Run three arms at identical examples seen: no-edit baseline, unclipped ZO, clipped ZO with the swept `c`.
3. Report clean-test accuracy per arm, the clipped-minus-unclipped delta with independent-unit uncertainty, and the same delta at a second, larger flip fraction (the reported advantage vanishes beyond ~50%, which is itself a claim to check).
4. Also report the rare-slice recall from the retention probe: clipping works by implicitly down-weighting hard-to-fit examples, which is exactly the mechanism that can starve a rare but correct class.

## Verification gates

An arm is `NOT RUN` until all of these exist; any missing gate downgrades the arm, it does not get waived.

| Gate | Check | Failure it catches |
| :--- | :--- | :--- |
| Perturbation liveness | `\|\|theta_+ - theta_-\|\|_F == 2*eps*\|\|z\|\|_F` within a stated tolerance, after casting to the storage dtype | Low-precision rounding making the directional derivative silently zero |
| fp32 master | All perturbation arithmetic on fp32 copies; stored dtype only for the forward pass | Same, plus partial-quantization bias in `g` |
| Matched budget | Same examples seen and same locked set for every arm; match basis named (`examples` / `FLOPs` / `GPU-hours`) | Step-count comparisons that silently favour one arm |
| Control arm | Unclipped ZO at the same budget, plus an **aggregate**-clipping control (clamp the batch aggregate or summed update, not each example) where clipping is the claim; a post-`z` norm clip is a reparameterisation of the per-sample clamp at `c/\|z\|`, not a control | Attributing a gain to clipping when any ZO run would show it, or to a "placement" difference that is only a rescaling of `c` |
| Cross-task preservation | Regression set from a **different** task than the optimized one | Narrow overfit that a same-task held-out split cannot see |
| Rare/hard-example retention | Per-slice recall on the rarest labels, clipped vs unclipped | Clipping suppressing rare but valuable examples |
| Calibration | ECE (or Brier) on the locked set, per arm | Clipping/ZO degrading confidence quality while accuracy rises |
| Label-noise probe | Flipped-fraction sweep vs the unclipped arm | Robustness claims with no noise arm behind them |
| Seed disclosure | Each arm labelled `single-seed` unless repeated | Seed shopping presented as an effect |
| Baseline headroom | Base and each no-training control scored on the **preregistered first-rung metric**, with the numeric rule fixed in the contract (policy default: base within `0.02` of the best no-training control, or base AUC `>= 0.99`) | A ceiling-level base or an untrained control already matching the target: the "gain" is threshold placement or prompt content, not the parameter edit |

**Baseline headroom gate — numeric, and frozen in the contract before any arm runs.** Two things are fixed up front, and changing either afterwards invalidates the run: (1) a **preregistered metric ladder**, an ordered list such as rung 1 = the cell's ordering/target metric, rung 2 = `gold_ce`, rung 3 = one named tail/rare-slice metric; (2) a **numeric headroom rule**, recorded with the ceiling estimate it refers to. This skill's policy default, to be overridden only by an explicitly recorded operator choice: *a rung is non-informative when the unchanged base is within `0.02` of the best no-training control on that rung, or when the base already reaches `0.99` on a metric whose ceiling is `1.0`* (AUC). Score the base plus the no-training controls — the cell's own cue, at least one alternative cue, base at its own best threshold — and if the rule fires, descend the ladder and report the higher rung `NOT INFORMATIVE` **for every arm**, never as a gain for whichever arm happens to move it. The margin is a convention chosen by the operator, not a measured constant: state yours with the ceiling estimate. Descending is *not* a post-hoc metric change, because the ladder and the margin were frozen first; changing them after seeing an arm's number is, and voids the run. Worked example from the pilot: the eligible cell passed its preregistered accuracy/CE rule and still had base AUC `0.9999`, so both default clauses fire (base AUC `>= 0.99`; base accuracy `0.995` within `0.02` of the `1.000` no-training cue-only control). On that cell the accuracy column is `NOT INFORMATIVE` for every arm, and the base's `0.865 -> 0.995` movement under a monitor-chosen threshold (zero-threshold accuracy versus monitor-threshold accuracy) is threshold placement, not capability.

## Evidence boundary

The paper's numbers are prompt-based ZO fine-tuning of RoBERTa-large (355M) and OPT-1.3B, with `c`, `lr`, and clipping placement (per-example clamp before aggregation versus batch-level clipping) as the studied variables. It reports **no** cost, memory, or wall-clock measurements, and **no** component-restricted or full-vs-subset ZO comparison. Its `lr*c` relation is empirical, per backbone, and holds only in the clipping-dominated regime, so it does not transfer to another architecture or optimizer by assumption. All SNLI, label-flip, and ECE figures quoted above are the paper's, within that scope, and are not our measurements. Any cost, memory, or cross-backbone table published from this skill is our own measurement and must say so, with the exact arm, dtype, batch, step count, and hardware.

## Local pilot evidence

**Round 2, replacing a retracted round 1.** The clean-label accuracy table published from round 1 of this pilot was found invalid by independent review and is withdrawn (`artifacts/round1/`, `ROUND2.md`); every number below is round 2. One bounded pilot: one local checkpoint, one synthetic two-token-answer task, one machine (RTX 5070 Ti 16 GB); 3 ZO seeds, 2 LoRA seeds, 1 seed each for `direct`, the controls and the blends. Iterative arms are matched on **examples seen (512 = 64 steps x batch 8)**, not FLOPs and not GPU-hours, and the paper this section tests used ~640k examples. So this section constrains method and gate choices — which traps are real, which gates have to block an arm, which differences this scale cannot resolve — and does **not** estimate cross-backbone effect sizes or replicate the paper.

**Why round 1 is retracted, and the gate that would have caught it.** Three facts killed the round-1 table, and none of them is a subtlety of the estimator:

| what happened | the number | consequence |
| :--- | :--- | :--- |
| the task cell failed the pilot's own **preregistered** eligibility rule (`0.15 <= p(yes) <= 0.85`, `ce_separation > 0.5`, `0.55 <= acc <= 0.85`) | round-1 cell `parity6/parity2`: acc 0.79, p(yes) 0.29, `ce_separation` **0.4963 <= 0.5** -> `eligible: false` | every arm had been measured on a cell the protocol did not admit |
| base ordering was already at ceiling, so accuracy measured **threshold placement** | base locked-test AUC **0.9999**; base acc 0.865 at a zero threshold vs 0.995 at the monitor threshold (**+0.130 with no weight touched**); the locked-test-optimal-threshold oracle also 0.995; best arm 1.000 (**+0.005**) | the comparability of the whole table was threshold bookkeeping |
| a **training-free** prompt change scored the same | of 7 in-context cue variants at base weights, 5 reach locked-test AUC 1.0000, best CE 0.2367 at acc 1.0000 (`results.json/controls/cue_only/variants`) | "1.000 accuracy" was reachable with zero parameter change |

Round 2 therefore re-ran everything on the only cell of 25 that passes the preregistered rule, and switched the primary metrics to threshold-free: locked-test **AUC of the yes/no margin** and **gold-token CE**. Accuracy is secondary, at a threshold chosen on the 64-example monitor split (`argmax` monitor accuracy, tie-break smallest absolute threshold), and every best-threshold or best-cue row is labelled `ORACLE`.

**Artifact provenance.** Arms and controls: `results.json` (22 runs, all `status: VALID`) and the tables regenerated from it in `RESULTS.md`; each quoted arm value also appears in `pilot_summary.json` (with min/max where the value is a seed mean). Retraction and round-1/round-2 delta: `ROUND2.md`. Probe, sweeps, per-group bf16 loss: `artifacts/calibration.json`. Load gates, static dead-zone accounting, baseline eval: `artifacts/model_verification.json`. Baseline degeneracy: `artifacts/base_diagnostics.json`. Cell competence and eligibility: `artifacts/base_competence_grid.json`. Gate negative/positive tests: `artifacts/gate_tests.json`. Repeat-run hashes: `artifacts/determinism.json`. Storage cross-check: `artifacts/fp32_check.json`. Harness and caps: `README.md`. The JSON files are authoritative where prose disagrees.

**Contract** (`artifacts/model_verification.json`, `results.json/meta`). `/home/kosal/Qwen3.5-0.8B`, bf16, 852.99M params, tied `lm_head`/embedding, hybrid linear/full attention (operator groups include `...linattn_o` and `...attn_o`); strict load 0 missing / 0 unexpected / 0 mismatched over 488 index keys; text-only forward finite, logits `[2, 14, 248320]`; sha256 `04b1c301...f1fe4696`. Target cell `compare3` with a 1-example parity cue (grid row acc 0.84, p(yes) 0.66, `ce_separation` 1.2237 -> `eligible: true`); preservation `parity4` with a **different** rule and its own 2-example cue. Splits 256 train / 64 monitor / 200 locked test / 100 preservation (+64 preserve-monitor); split seed 20240, cue seed 4242; the locked test is never used for selection. `eps = 1e-3` absolute; ZO subset `early:linattn_o`, 12,582,912 params, chosen by forward-only `grad_norm/sqrt(numel)` ranking; unclipped `lr = 3e-6`; clipped `c = 1.0` with `lr = 5e-4`; post-`z` reparameterisation run `c = 5000`; 12 torch threads, one process at a time.

**Trap 1 — bf16 storage destroys `eps = 1e-3` perturbations** (`artifacts/calibration.json/probe`, `artifacts/model_verification.json/candidate_groups`). An fp32 master keeps the arithmetic honest, but the *realized* perturbation that reaches bf16 storage is quantized, so the harness measures the realized rather than the intended direction:

| tensor group | numel | entries of the perturbation lost in bf16 | cos(realized, intended) |
| :--- | ---: | ---: | ---: |
| `global:final_norm` | 1,024 | **99.609%** (0.99609; static weight-only accounting 0.9922 = 99.22%) | 0.125 |
| `global:lm_head` (tied embed) | 254,279,680 | 3.468% (0.03468) | 0.9995 |
| `early:linattn_o` (selected ZO subset) | 12,582,912 | 2.072% (0.020720 probe; 0.020677 at step 0 of an arm) | 0.9998 |
| `layer14:mlp_down` (least affected) | 3,670,016 | 1.347% (0.01347) | 0.9999 |

The loss spans **1.347%-99.609% over the 62 candidate groups** and must not be quoted as 1.35%-3.47%: `global:final_norm` (1,024 params, `|w| ~ 1`, bf16 `ULP/2 >= eps`) is one of the groups. An in-place bf16 implementation (`theta.add_(eps*z)` on stored weights) would have reported "zero-order optimization does nothing here" as a method result. The arm now fails loudly rather than logging and continuing: a lossy realized direction raises `DeadPerturbationError` and the arm status becomes `INVALID_DEAD_PERTURBATION`. The round-2 liveness counter is a per-run field `dead_perturbation_steps` (`zo_harness.py:1093`), which reads `0` in every ZO run *because* a dead step aborts the arm instead of being counted; it is surfaced per repeat as `dead_steps` in `artifacts/determinism.json` (`0` and `0`), and all 14 ZO runs in `results.json` are `status: VALID`. Liveness is recorded per checkpoint, not per run: `frac_examples_nonzero_delta` sits in each `perturbation_checks[]`/`history[]` record and is 1.0 in all 1,003 of its 1,004 occurrences in `results.json` and the artifacts — but it is not an invariant, since the negative gate test records `0.75` at step 0 and aborts there. `artifacts/gate_tests.json` proves both polarities: the negative test (subset `global:final_norm`) aborts after 1 executed step having lost 0.9971 of the perturbation (`rel_err` 0.9979, cos 0.0855, `nz_delta` 0.750), the positive test (`early:linattn_o`, 4 steps) completes `VALID`.

**Trap 2 — the baseline was degenerate before it was measured** (`artifacts/base_diagnostics.json`, `artifacts/gate_tests.json`). On a bare prompt the model emits one constant answer token, so accuracy equals the label prior and cannot separate right from wrong: monitor 0.500 accuracy at `p(yes) = 0.000`, locked test 0.500, preservation 0.360, `p(correct > incorrect) = 0.500` on all three. A 0.50 to 0.90 "gain" on that baseline would have been label-prior flipping, so the harness now refuses to train (`INVALID_DEGENERATE_BASELINE`: `p(correct > incorrect)` 0.5000 < 0.6 and `frac_pred_yes` 0.0000 outside (0.02, 0.98)), tested as a negative and a positive case. With the cell's own cue the `base` arm is `p(yes) = 0.635` at AUC 0.9999, and that is the baseline every arm below is compared against.

**Locked-test results, clean labels** (`results.json`; AUC and CE on n=200, preservation on the disjoint n=100 set; ranges are min-max over seeds). `direct` is the exception to the example budget: closed-form on the 256 training examples with 0 backward passes, so it is not example-matched to the 512-example arms and must not be ranked against them.

| arm | seeds | test AUC (primary) | test gold CE (primary) | test acc @ monitor thr | preserve AUC | peak VRAM |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `base` (no edit, control) | 1 | 0.9999 | 0.3651 | 0.995 (thr 1.5) | 0.9982 | 2.60 GB |
| `base_best_threshold` (**ORACLE**, not a method) | n/a | 0.9999 | 0.3651 | 0.995 (thr 1.3125, locked test) | 0.9982 | 2.60 GB |
| `cue_only` (parity2/2, no training, monitor-selected) | n/a | 1.0000 | 0.2367 | 1.000 (thr 0.6875) | 0.9982 | 2.60 GB |
| `direct` (closed-form ridge, 256 examples, 0 backward) | 1 | 1.0000 | 0.1181 | 0.995 | 0.9962 | 2.60 GB |
| `zo_mezo` (unclipped, 2 forward / 0 backward) | 3 | 1.0000 [1.0000-1.0000] | 0.0971 [0.0816-0.1119] | 0.9983 [0.995-1.000] | 0.9999 | 2.60 GB |
| `zo_clip` (per-sample `c = 1.0`, `lr = 5e-4`) | 3 | 0.9998 [0.9995-1.0000] | 0.1219 [0.0371-0.2169] | 0.9733 [0.950-1.000] | 0.9995 | 2.60 GB |
| `zo_batchmean_scalarclip` (clip the aggregate; **control**) | 1 | 0.9939 | 0.2570 | 0.965 | **0.7714** | 2.60 GB |
| `zo_postz_normclip` (`c = 5000`; **reparameterisation check**, same estimator as `zo_clip`) | 1 | 0.9982 | 0.2135 | 0.955 | 0.9804 | 2.60 GB |
| `lora` (r=8, `lr = 3e-5`, 1 forward / 1 backward) | 2 | 1.0000 | 0.0000 | 1.000 | 1.0000 | 3.25 GB |
| blend `0.5*base + 0.5*lora` | 1 | 1.0000 | 0.0025 | 1.000 | 1.0000 | 2.63 GB |
| blend `0.5*base + 0.5*zo_clip` | 1 | 1.0000 | 0.2129 | 1.000 | 0.9988 | 2.63 GB |

**Reading: this cell has no AUC headroom, so AUC cannot rank the arms.** Every arm lands in 0.9939-1.0000 against a 0.9999 base; the largest treatment delta is **+0.0001** (`eval.vs_base.auc_delta`), and the only negative deltas are `zo_clip` seed 13 (-0.0004), the post-`z` reparameterisation run (-0.0017) and the batch-mean control (-0.0060). On clean labels 21-35 of the 200 locked-test examples change predicted side (the wider 19-58 range in `results.json` includes the 40%-noise rows), and **0-9 of those are harmful** (`n_broken`: 0 for `direct`, all 3 `zo_mezo`, `zo_clip` seeds 11-12, both `lora` and both blends; 2 for the post-`z` run, 4 for `zo_clip` seed 13, 9 for the batch-mean control), with mean margin shifts of -2.89 to +1.34 and rank correlation to base margins **0.8985-0.9862 across the 11 clean-label rows** (0.9681-0.9822 for the `zo_mezo`/`zo_clip` treatments alone). So the flips are margin centring, not reordering — and that is exactly why an accuracy table looked like a capability gain. **CE is the only primary metric with headroom here**: 0.3651 base, 0.2367 for the best untrained cue, 0.0971 for unclipped ZO. Clipping is **not** distinguishable from unclipped ZO on these metrics at this budget (CE 0.1219 versus 0.0971 with overlapping seed ranges; AUC delta +0.0001 either way), but its *form* matters: clipping the aggregate instead of per-sample damages the second task (**0.7714** preservation AUC / 0.70 acc versus 0.9999 / 0.98-1.00), which is why that arm is a control and not a strategy.

**Under 40% flipped training labels** (flip seed 777, same 512 examples seen; the cue still demonstrates the clean rule):

| arm | seeds | test AUC | test gold CE | test acc @ monitor thr | preserve AUC |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `zo_mezo` | 3 | 0.9952 [0.9893-1.0000] | 0.5145 [0.4083-0.6106] | 0.9633 | 0.9987 |
| `zo_clip` | 3 | 1.0000 [0.9999-1.0000] | 0.5476 [0.4774-0.6154] | 0.9933 | 0.9985 |
| `lora` | 2 | 0.9980 [0.9972-0.9989] | 0.5945 [0.5858-0.6032] | 0.9825 | 0.9971 |

Ordering survives the noise for all three arms (AUC >= 0.9972) while CE rises to 0.51-0.59 from 0.00-0.12 on clean labels, so the readable claim is "CE degrades, ordering does not", not "arm X is robust". The same noise condition is where the reordering numbers appear: `n_broken` rises to 44-58 for `zo_mezo` seed 11, all three `zo_clip` seeds and both `lora` seeds, i.e. "no reordering" is a clean-label statement only. Backprop has the lowest AUC and the highest CE under noise and the lowest preservation of the three; no arm separates from another inside its own seed range.

**Determinism, storage cross-check and cost** (`artifacts/determinism.json`, `artifacts/fp32_check.json`, `results.json`). Two repeat runs of the same seed produce bitwise-identical ZO weights (`428356c81b3f3d03`) and margins (`30ac318ea54a6b83`), and identical LoRA margins (`0165e0f6b5106b00`) from adapter `5b39f070772576a4` merged to `d51762589def51ed`. The merge is **not** bit-exact: `merge_rel_err = 0.422639`, i.e. 42.3% of the adapter update norm is lost in the merge, so a merged model must be re-scored rather than assumed equal to adapter-on-base. Deterministic kernels are enabled (`artifacts/determinism.json/verdict.deterministic_mode`); measured total pilot wall time is **350.8 s** (`results.json/total_wall_s`) on 12 threads. Peak VRAM is 2.60 GB for every ZO arm and control, 2.63 GB for the noisy ZO arms and the blends, 3.25 GB for LoRA. The memory control is a **pre-run free-VRAM floor, not a cap**: `MIN_FREE_VRAM_GB = 3.0` (`zo_harness.py:87`), checked before each arm by `memory_guard()` against `torch.cuda.mem_get_info()` (`zo_harness.py:151`) together with a host-RAM floor, and it raises `MemoryError` instead of letting the kernel OOM. Each arm reaches the pre-registered monitor threshold in 0.41-0.52 s of training. **Storage cross-check**: unclipped ZO at seed 11 re-run with the whole model in fp32 loses no perturbation (`frac_entries_perturbation_lost` 0.0, `rel_err` 0.0, cos 1.0 at every checkpoint, 1e-6 at step 63) and lands on test AUC 1.0000 / CE 0.1094 / acc 1.000 / preservation 0.9996 at 4.35 GB peak, against 1.0000 / 0.0977 / 1.000 / 0.9996 for the bf16 run of the same arm and seed. One seed, so this licenses "bf16 storage did not manufacture the gain" and nothing about precision effects.

**What this run supports, and what it does not.** Supported: (a) cell selection must be preregistered and gated on **threshold-free** headroom with an untrained control in the table — round 1 failed both and produced a confident wrong table, which is why the baseline-headroom gate exists above; (b) the dead-perturbation and degenerate-baseline gates are prerequisites, not hygiene: both traps were silent and both would have yielded a confident wrong conclusion, and both are now proven to fire; (c) on a cell whose ordering is at ceiling, threshold-free CE is the discriminating metric, and 512 examples of restricted ZO on a 12.6M-parameter subset move it 0.3651 -> 0.0971; (d) clipping's benefit is not visible in AUC or CE at this budget, while the aggregate-clip form is a different method that damages preservation; (e) accuracy claims on this task family are unusable, because an untrained prompt change reaches the accuracy ceiling. Not resolved, and therefore `NOT RUN` rather than "unchanged": any of this holding beyond one backbone, one synthetic yes/no task, one eligible cell, 3 ZO seeds and 512 examples seen; expected calibration error or any other calibration metric; full-parameter ZO (`lm_head` was probed, never trained); `eps`, `c`, `lr`, batch, schedule and weight-decay sweeps beyond the recorded monitor-side selections; per-arm hyperparameter parity (each arm runs at its own selected setting, so the LoRA-versus-ZO gap is not like-for-like and is not claimed as one); paired significance tests; generation quality; deployment-runtime arithmetic (no fp16/int8/ORT/TensorRT re-export or latency measurement). The eligible cell is at ceiling on AUC, so this pilot can rank methods only by CE: no cell in the grid has AUC headroom, and adding one post hoc would be a rule change, not a result.
