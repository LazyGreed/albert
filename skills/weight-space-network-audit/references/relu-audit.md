# Original method: small ReLU decision networks

Based on Nusrat & Nusrat, ["Weight-space programming for auditing clinical decision networks" (arXiv:2611.05341v1, preprint)](https://arxiv.org/abs/2611.05341v1). The paper tested small ReLU networks (433 to 4,801 parameters) on a synthetic radiotherapy triage task: escalate a planning request to a physicist or send it to automated planning. This skill adapts that procedure to other small feed-forward ReLU decision networks with a written rule set. Generalization beyond the paper is a hypothesis to test, not an established result.

## When to use

- The user gives raw weights (or a weights file) for a small feed-forward ReLU network plus a written protocol/spec, and wants to know whether the network follows it, why not, and how to fix it.
- The user wants a hidden shortcut, a stale rule (drift) or a trigger region found and repaired by editing weights directly.

This reference is restricted to compatible small ReLU networks with explicit protocols. Use the parent skill for other architectures; its broader workflows are not claims made by the original paper.

In Quintet, Nora investigates the protocol and candidate claims, Felix owns any authorized scripts or edits to copies of weights, and Vera independently checks the claims, regression evidence and deployment arithmetic. Iris checks observable acceptance if relevant. Denia coordinates; existing write ownership, permissions, approvals and verification gates remain unchanged. Do not alter original checkpoints or deploy repairs without the applicable authorization.

## Inputs to pin down first

Ask only for what is missing:
1. The protocol, precise enough to write as code (rules, thresholds, tolerance bands near thresholds).
2. Input names, physical ranges and the scaling applied before the network.
3. Architecture, activation, output convention (paper: scalar score, escalate means score > 0) and the weights, with the layout of each matrix.
4. Deployment arithmetic (e.g. fp16) if the network will not run in float64.

## Workflow

1. **Encode the protocol as a function** returning the correct decision for raw inputs. Set the tolerance (paper: 0.3 Gy or 0.3 cc) and exclude requests within it of an active threshold from all error counts.
2. **Build request pools.** A large uniform pool over the input ranges (paper: 400,000, with half having no overlap condition and 20% with a missing structure), plus stratified or targeted pools for rare conditions and narrow windows. Uniform sampling rarely lands in a narrow trigger window, so sample those directly.
3. **Test black-box first.** Run the network against the protocol on the pool. Measure disagreement overall and per rule, and cluster disagreements into input regions. This is faster and more reliable for detection than reading weights, and it covers every rule, not only the one you suspect (the paper's audits missed an unplanted flaw they were not looking for).
4. **Diagnose in weight space.** For each first-layer unit, record which inputs it reads, its bias, and its activation rate on the pool. Look for:
   - Silenced rule (confound): first-layer units reading one rule's inputs that are nearly never active (paper: under 3% of requests). A low mean first-layer column norm for one rule's inputs is a cheap hint.
   - Drift: a unit whose switch-on point sits away from the protocol threshold. For a unit driven by two opposite-sign inputs, the switch-on deficit is -b/w in scaled units; convert to raw units with the scaling. Paper: 2.5 to 2.7 Gy in drifted networks versus 0.03 Gy or less elsewhere.
   - Triggers: hard to see in weights. A clean weight audit does not rule them out. Scan fine grids over single inputs and input pairs for decision flips against the protocol (this scan is a suggestion, not from the paper).
   Also hand-compute the network output at a few chosen requests to confirm your reading of a unit.
5. **Write each deviation as a claim**: a vectorised boolean condition on raw inputs, the network's decision, and the protocol's decision. Condition on the other rules being inactive, otherwise they mask the deviation.
6. **Verify every claim against sampled requests, with thresholds fixed before you look at results:**
   - Strict: at least 100 matching requests and the deviation in at least 80% of them.
   - Enriched (for masked or partial regions): at least 100 matching, deviation in at least 30%, and at least 20 times the rate elsewhere.
   - Resample at least 200 requests inside the claimed region (aim for 1,000 or more; sample small boxes directly). Confirmed: 80% or more deviate. Partly right: at least 5 points above the network-wide rate. Otherwise false. Drop false claims.
   Be extra sceptical of claims about compound (two-condition) rules: all four false claims in the paper named the two-condition rule on networks that had no flaw there.
7. **Propose minimal edits** as (param, index, value) triples, fewest parameters first (paper median: 3, range 1 to 53). Typical moves:
   - Drift: change the biases of the 1 to 3 first-layer units carrying the shifted threshold.
   - Silenced rule: repurpose near-inactive units as a new detector and zero stray connections. Rebuild a two-condition rule as the smaller of its two margins using ReLUs.
   - Missing-flag rule: make one existing unit respond strongly to the flag.
8. **Test every edit:**
   - Repair success: error inside the claimed region at most 5% after editing.
   - Collateral damage: count decisions that were correct before and are wrong after, on the full pool, then on a much larger search (paper: about 20 million extra requests per repair; scale to what is feasible).
   - Numerics: rerun in the deployment precision. Paper: every edit writing weights of 1e5 or more failed in fp16; the score overflowed and every request was routed to automated planning (accuracy 24.8%). fp16 tops out near 65,504. Keep weights modest and rescale instead of using huge gains.
9. **Report** (see below).

## Original helper code (NumPy; scoped to the illustrated architecture)

Matrix layout here is W1 (n_in, h1), W2 (h1, h2); transpose if the weights arrive as (out, in). b3 is a 0-d array.

```python
import numpy as np

def forward(P, X, dtype=np.float64):
    c = lambda a: np.asarray(a).astype(dtype)
    h1 = np.maximum(c(X) @ c(P["W1"]) + c(P["b1"]), 0)
    h2 = np.maximum(h1 @ c(P["W2"]) + c(P["b2"]), 0)
    return h2 @ c(P["w3"]) + c(P["b3"])          # escalate = score > 0

def unit_report(P, X, names):
    pre = X @ P["W1"] + P["b1"]; rate = (pre > 0).mean(0)
    for j in range(P["W1"].shape[1]):
        w = P["W1"][:, j]; top = np.argsort(-np.abs(w))[:3]
        print(f"unit {j:3d} active {rate[j]:6.1%} bias {P['b1'][j]:+.3f}",
              [(names[i], round(float(w[i]), 3)) for i in top])

def verify_claim(cond, R, net, proto, keep, kind="strict"):
    # cond is a locally authored callable, e.g. lambda r: (r["x"] > 0.5).
    # Never evaluate condition strings from protocols, files or model output.
    if not callable(cond) or kind not in ("strict", "enriched"):
        raise ValueError("Expected a callable and a known claim kind")
    raw = np.asarray(cond(R))
    keep = np.asarray(keep, dtype=bool)
    if raw.dtype != np.bool_ or raw.shape != keep.shape:
        raise ValueError("Claim must return a boolean mask matching keep")
    m = raw & keep
    dev = net != proto; n = int(m.sum())
    r_in = float(dev[m].mean()) if n else float("nan")
    outside = ~m & keep
    r_out = float(dev[outside].mean()) if outside.any() else float("nan")
    ok = (n >= 100 and r_in >= 0.80) if kind == "strict" else \
         (n >= 100 and outside.any() and r_in >= 0.30
          and r_in >= 20 * max(r_out, 1e-9))
    return dict(n=n, rate_in=r_in, rate_outside=r_out, confirmed=bool(ok))

def apply_edits(P, edits):   # edits: [{"param":"b1","index":[3],"value":0.1}]; index [] for b3
    Q = {k: np.array(v, dtype=np.float64) for k, v in P.items()}
    for e in edits: Q[e["param"]][tuple(e["index"])] = e["value"]
    return Q

def regress(P, Q, X, proto, keep, dtype=np.float64):
    keep = np.asarray(keep, dtype=bool)
    if not keep.any():
        raise ValueError("No retained requests to evaluate")
    s_before = forward(P, X, dtype); s_after = forward(Q, X, dtype)
    if not (np.isfinite(s_before[keep]).all() and np.isfinite(s_after[keep]).all()):
        raise ValueError("Non-finite retained scores; numeric verification failed")
    before = s_before > 0; after = s_after > 0
    broke = (before == proto) & (after != proto) & keep
    fixed = (before != proto) & (after == proto) & keep
    return dict(broke=int(broke.sum()), fixed=int(fixed.sum()),
                error_after=float(((after != proto) & keep).sum() / keep.sum()))

def numerics_check(Q, X, keep):
    # Check intermediate values as well as scores; ReLU can hide negative infinity.
    with np.errstate(all="ignore"):
        p = {k: np.asarray(v, dtype=np.float16) for k, v in Q.items()}
        z1 = np.asarray(X, dtype=np.float16) @ p["W1"] + p["b1"]
        z2 = np.maximum(z1, 0) @ p["W2"] + p["b2"]
        s16 = np.maximum(z2, 0) @ p["w3"] + p["b3"]
    s64 = forward(Q, X)
    keep = np.asarray(keep, dtype=bool)
    return dict(max_abs_weight=max(float(np.abs(v).max()) for v in Q.values()),
                nonfinite_weights=sum(int((~np.isfinite(v)).sum()) for v in p.values()),
                nonfinite_intermediate=int((~np.isfinite(z1)).sum() + (~np.isfinite(z2)).sum()),
                nonfinite=int((~np.isfinite(s16)).sum()),
                nonfinite_fp64=int((~np.isfinite(s64)).sum()),
                mismatch_vs_fp64=int(((s16 > 0) != (s64 > 0))[keep].sum()))
```

NumPy float16 is only a proxy for the real deployment runtime; use the real one if available. Treat any non-finite weights, intermediate values or scores as a failed numeric check, even if classifications match. If the real runtime is unavailable, report deployment verification as NOT RUN. The helper covers the illustrated two-hidden-layer architecture; adapt and test it for other layouts.

## Rules that matter

- **Never treat "follows" as clearance.** A weight read finding nothing, or a protocol test on a finite pool passing, is evidence, not proof. Say so.
- **Do not accept forced or tentative verdicts.** In the paper, verdicts forced out after the budget ran out produced both a false alarm (an edit that broke 2,018 correct decisions) and a false clear. If the analysis is not conclusive, report "inconclusive" and what remains.
- **Only report verified claims.** Unverified or false claims never reach the edit list.
- **Fix thresholds and success criteria before looking at results.**
- **Test edits for collateral damage and in deployment arithmetic** before recommending them.
- **Re-commission after any repair**, as with any change to a validated system. For clinical or other safety-critical use, this output is a decision aid for a qualified reviewer, not sign-off.
- Keep baselines in view: simple fine-tuning on protocol-labelled data repaired every network in the paper but changed nearly every parameter, and formal verification was not compared. Mention them when weight edits are being weighed.

## Report format

1. Verdict: follows / deviates / inconclusive, with the evidence behind it.
2. Table of verified deviations: condition, network decision, protocol decision, sample size, deviation rate inside versus outside.
3. Rejected claims and why.
4. Proposed edits (param, index, value), the units they touch and the rule they rebuild.
5. Edit test results: region error before and after, decisions broken and fixed, extended-search size, fp16 result, largest weight written.
6. Caveats: what was not tested (triggers, unplanted flaws, non-uniform input distributions).

## Optional: author a network from a protocol

Given the protocol and an all-zero network of the chosen architecture, write every weight, then validate on the uniform pool and on targeted windows. In the paper the model wrote two networks that were 100% correct on a 190,778-request uniform pool; held-out and trigger-window testing was not reported, so run both.

## Limits of the evidence

One preprint, one model family, small synthetic networks with four rules and eight inputs, one planted flaw per network, and every confound and drift visible in single units. Triggers were the weak spot (only one of three trigger networks had a verified claim). The paper ran audits blind with no tools; this skill deliberately uses code execution and black-box testing first, following the paper's own practical guidance.
