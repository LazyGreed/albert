## Universal Checkpoint I/O, Local Solver & Audit Toolkit

Starting points for small/medium trusted models; use streaming/blockwise probes and matrix-free solvers for large checkpoints.

```python
import copy
import hashlib
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn

def sha256_file(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def load_weights_any_format(path: str | Path):
    """Safe loader for .safetensors, .pt/.pth/.ckpt/.bin, .onnx, .npz."""
    p, ext = Path(path), Path(path).suffix.lower()
    if ext == ".safetensors":
        from safetensors import safe_open
        from safetensors.torch import load_file
        with safe_open(str(p), framework="pt", device="cpu") as f:
            meta = f.metadata() or {}
        return "safetensors", load_file(str(p), device="cpu"), {"metadata": meta}
    if ext in (".pt", ".pth", ".ckpt", ".bin"):
        obj = torch.load(str(p), map_location="cpu", weights_only=True)
        if isinstance(obj, dict):
            for k in ("state_dict", "model_state_dict", "model", "ema"):
                if k in obj and isinstance(obj[k], dict):
                    return "pytorch_wrapped", dict(obj[k]), {"wrapper": obj, "key": k}
            return "pytorch_dict", dict(obj), {}
        raise ValueError(f"Unsupported PyTorch payload: {type(obj)}")
    if ext == ".onnx":
        import onnx
        from onnx import numpy_helper
        model = onnx.load(str(p))
        tensors = {i.name: torch.from_numpy(numpy_helper.to_array(i).copy()) for i in model.graph.initializer}
        return "onnx", tensors, {"onnx_model": model}
    if ext == ".npz":
        with np.load(str(p), allow_pickle=False) as z:
            return "npz", {k: torch.from_numpy(z[k].copy()) for k in z.files}, {}
    raise ValueError(f"Unsupported extension '{ext}'; use format-specific safe adapter.")

def save_weights_any_format(fmt: str, tensors: dict[str, torch.Tensor], meta: dict, out_path: str | Path):
    """Save updated copy preserving format, dtypes, and metadata; return SHA-256."""
    out = Path(out_path)
    if fmt == "safetensors":
        from safetensors.torch import save_file
        save_file({k: v.detach().cpu().contiguous() for k, v in tensors.items()},
                  str(out), metadata=meta.get("metadata") or None)
    elif fmt == "pytorch_wrapped":
        wrapper = copy.deepcopy(meta["wrapper"])
        wrapper[meta["key"]] = {k: v.detach().cpu() for k, v in tensors.items()}
        torch.save(wrapper, str(out))
    elif fmt == "pytorch_dict":
        torch.save({k: v.detach().cpu() for k, v in tensors.items()}, str(out))
    elif fmt == "onnx":
        import onnx
        from onnx import numpy_helper
        model = copy.deepcopy(meta["onnx_model"])
        for init in model.graph.initializer:
            if init.name in tensors:
                init.CopyFrom(numpy_helper.from_array(tensors[init.name].detach().cpu().numpy(), name=init.name))
        onnx.checker.check_model(model)
        onnx.save(model, str(out))
    elif fmt == "npz":
        np.savez(str(out), **{k: v.detach().cpu().numpy() for k, v in tensors.items()})
    else:
        raise ValueError(f"Unknown format: {fmt}")
    return sha256_file(out)

@torch.no_grad()
def solve_constrained_local_delta(H_r: torch.Tensor, R: torch.Tensor, H_k: torch.Tensor,
                                  lam_keep: float = 10.0, lam_ridge: float = 1e-2,
                                  max_rank: int | None = None, trust_radius: float | None = None):
    """Solve min_D ||H_r D - R||_F^2 + lam_keep ||H_k D||_F^2 + lam_ridge ||D||_F^2
    and return delta_W = D.T (out_dim, in_dim) with optional rank-k & trust-region cap."""
    Hr, Rv, Hk = H_r.to(torch.float64), R.to(torch.float64), H_k.to(torch.float64)
    A = Hr.T @ Hr + lam_keep * (Hk.T @ Hk) + lam_ridge * torch.eye(Hr.shape[1], dtype=torch.float64, device=Hr.device)
    D = torch.linalg.solve(A, Hr.T @ Rv)
    dW = D.T
    if max_rank is not None and max_rank < min(dW.shape):
        U, S, Vh = torch.linalg.svd(dW, full_matrices=False)
        dW = (U[:, :max_rank] * S[:max_rank]) @ Vh[:max_rank, :]
    if trust_radius is not None:
        norm = torch.linalg.norm(dW)
        if norm > trust_radius > 0:
            dW = dW * (trust_radius / norm)
    return dW.to(H_r.dtype)

class AuditProbe:
    def __init__(self, model: nn.Module, module_names: list[str], allow_neg_inf: set[str] | None = None):
        self.captures, self.nonfinite_counts, self.allow_neg_inf = {}, {}, allow_neg_inf or set()
        named = dict(model.named_modules())
        self._handles = [named[n].register_forward_hook(self._hook(n)) for n in module_names]

    def _hook(self, name):
        def fn(_m, _i, out):
            t = out[0] if isinstance(out, (tuple, list)) else out
            if torch.is_tensor(t):
                self.captures[name] = t.detach()
                bad = (torch.isnan(t) | torch.isposinf(t)) if name in self.allow_neg_inf else ~torch.isfinite(t)
                self.nonfinite_counts[name] = int(bad.sum().item())
        return fn

    def region_hash(self, quantile_buckets: bool = False) -> list[bytes]:
        sigs = []
        for name in sorted(self.captures):
            flat = self.captures[name].reshape(self.captures[name].shape[0], -1)
            if quantile_buckets:
                bins = torch.tensor([-1.0, 0.0, 1.0], device=flat.device, dtype=flat.dtype)
                code = torch.bucketize(flat, bins).to(torch.uint8)
            else:
                code = (flat > 0).to(torch.uint8)
            sigs.append(code.cpu().numpy())
        return [row.tobytes() for row in np.concatenate(sigs, axis=1)]

    def signed_swiglu_mask(self, gate_name: str, up_name: str) -> torch.Tensor:
        """Encode SwiGLU neuron regime: 0=closed (g·x<=0), 1=open -w (u·x<0), 2=open +w (u·x>=0)."""
        g_open = self.captures[gate_name] > 0
        u_pos = self.captures[up_name] >= 0
        return torch.where(g_open, torch.where(u_pos, 2, 1), 0).to(torch.uint8)

    def close(self):
        for h in self._handles:
            h.remove()

@torch.no_grad()
def neuron_vote_diff(base_W: torch.Tensor, ft_W: torch.Tensor, token_dirs: torch.Tensor,
                     top_k_per_neuron: int = 50) -> dict:
    """E0 base-vs-finetune per-neuron vote over input-side row diffs (rows=neurons, cols=d_model).
    token_dirs: (vocab, d_model) normalized lens/embedding directions. Flags heavy MLP drift (>3%)."""
    dW = (ft_W - base_W).to(torch.float32)
    rel_drift = float(torch.linalg.norm(dW) / torch.linalg.norm(base_W.to(torch.float32)).clamp_min(1e-12))
    row_norms = torch.linalg.norm(dW, dim=1)
    active = row_norms > (row_norms.mean() + 2.0 * row_norms.std())
    if not active.any():
        return {"rel_mlp_drift": rel_drift, "drift_warning": rel_drift > 0.03, "top_token_ids": []}
    dirs = dW[active] / row_norms[active].unsqueeze(1).clamp_min(1e-12)
    t_norm = token_dirs.to(torch.float32)
    t_norm = t_norm / torch.linalg.norm(t_norm, dim=1, keepdim=True).clamp_min(1e-12)
    scores = dirs @ t_norm.T  # (n_changed, vocab)
    votes = torch.zeros(t_norm.shape[0], dtype=torch.float32, device=dW.device)
    top_idx = torch.topk(scores.abs(), k=min(top_k_per_neuron, t_norm.shape[0]), dim=1).indices
    votes.scatter_add_(0, top_idx.reshape(-1), torch.ones(top_idx.numel(), device=dW.device))
    order = torch.topk(votes, k=min(top_k_per_neuron, t_norm.shape[0])).indices.cpu().tolist()
    return {"rel_mlp_drift": rel_drift, "drift_warning": rel_drift > 0.03, "top_token_ids": order}

@torch.no_grad()
def unlearning_spike_ratio(base_acts: torch.Tensor, ft_acts: torch.Tensor,
                           forget_mask: torch.Tensor, retain_mask: torch.Tensor, top_n: int = 30) -> dict:
    """Detect backdoor-like suppression: top-changed neurons spiking on forget text but quiet on retain."""
    delta = (ft_acts - base_acts).abs().mean(dim=0)
    idx = torch.topk(delta, k=min(top_n, delta.numel())).indices
    f_base = base_acts[forget_mask][:, idx].abs().mean().item()
    f_ft = ft_acts[forget_mask][:, idx].abs().mean().item()
    r_base = base_acts[retain_mask][:, idx].abs().mean().item()
    r_ft = ft_acts[retain_mask][:, idx].abs().mean().item()
    f_gain = f_ft / max(f_base, 1e-9)
    r_gain = r_ft / max(r_base, 1e-9)
    return {"top_neuron_ids": idx.cpu().tolist(), "forget_gain": f_gain, "retain_gain": r_gain,
            "selective_suppression_flag": bool(f_gain > 2.0 and f_gain > 2.0 * r_gain)}

def verify_claim(cond, R, net, proto, keep, kind="strict"):
    """Safe locally authored boolean callable verifier (never eval external strings)."""
    if not callable(cond) or kind not in ("strict", "enriched"):
        raise ValueError("Expected callable condition and kind in {'strict','enriched'}")
    raw, keep = np.asarray(cond(R)), np.asarray(keep, dtype=bool)
    if raw.dtype != np.bool_ or raw.shape != keep.shape:
        raise ValueError("Claim callable must return boolean mask matching keep")
    m, dev = raw & keep, np.asarray(net) != np.asarray(proto)
    n = int(m.sum())
    r_in = float(dev[m].mean()) if n else float("nan")
    out = (~m) & keep
    r_out = float(dev[out].mean()) if out.any() else float("nan")
    ok = ((n >= 100 and r_in >= 0.80) if kind == "strict"
          else (n >= 100 and out.any() and r_in >= 0.30 and r_in >= 20.0 * max(r_out, 1e-9)))
    return dict(n=n, rate_in=r_in, rate_outside=r_out, confirmed=bool(ok))

@torch.no_grad()
def interval_linear_witness(W: torch.Tensor, b: torch.Tensor, x_lo: torch.Tensor, x_hi: torch.Tensor, rounding_eps: float = 1e-3):
    W_pos, W_neg = torch.clamp(W, min=0), torch.clamp(W, max=0)
    return x_lo @ W_pos.T + x_hi @ W_neg.T + b - rounding_eps, x_hi @ W_pos.T + x_lo @ W_neg.T + b + rounding_eps
```
