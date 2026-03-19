import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from typing import List, Dict, Any, Tuple, Optional
import pandas as pd
from collections import defaultdict
from .tracer import WeightAccessTracer
from .residency_sim import HRMResidencySimulator
from ric_x2.controller import RICX2
from ric_x2.types import AccessResult, TraceEvent
from sim_x2.baseline_x1 import BaselineX1
from sim_x2.config import X2SimConfig
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

# KEY ARCHITECTURAL CONSTANTS (from SRMIC-X1 spec)
HBM_BW_TBPS = 24.0      # TB/s aggregate
SRMESH_BW_TBPS = 96.0   # TB/s aggregate  
NUM_REGIONS = 64        # logical HRM regions (flagship)
PAGE_SIZE_MB = 2        # default page size
SUPPORTED_POLICIES = ["lru", "hotness", "srmic", "x1_baseline", "x2_admission", "x2_full"]

def run_sweep(
    model_name: str, 
    prompt: str, 
    hrm_budgets_gb: List[float], 
    num_tokens: int = 50, 
    policy: str = "srmic",
    seed: int = 1234,
    load_in_8bit: bool = False,
    hf_token: Optional[str] = None
) -> Tuple[pd.DataFrame, List[Dict[str, Any]]]:
    """
    Runs inference with the tracer active, then replays the access trace through 
    the residency simulator at multiple HRM budget points.
    """
    # 0. Set seed for reproducibility
    torch.manual_seed(seed)
    
    # 1. Load Model and Trace
    tokenizer = AutoTokenizer.from_pretrained(model_name, token=hf_token)
    
    model_kwargs = {
        "torch_dtype": torch.float16,
        "device_map": "cpu", # Use CPU for tracing if GPU is not available/needed
        "token": hf_token,
        "low_cpu_mem_usage": True
    }
    if load_in_8bit:
        model_kwargs["load_in_8bit"] = True
        
    model = AutoModelForCausalLM.from_pretrained(model_name, **model_kwargs)
    
    tracer = WeightAccessTracer()
    tracer.attach(model)
    
    input_ids = tokenizer.encode(prompt, return_tensors="pt")
    
    print(f"Tracing {num_tokens} decode steps for {model_name}...")
    with torch.no_grad():
        # Use model.generate() to capture decode steps correctly.
        # Max tokens = prompt length + num_tokens
        model.generate(
            input_ids, 
            max_new_tokens=num_tokens, 
            do_sample=False,
            use_cache=True, # Ensure KV cache is used to isolate decode-step weight access
            pad_token_id=tokenizer.eos_token_id
        )
            
    trace = tracer.get_trace()
    tracer.detach()
    
    # 2. Replay Trace and Compute Metrics
    results = _replay_trace(trace, hrm_budgets_gb, policy)
    
    # 3. Monotonicity Validation
    df = pd.DataFrame(results)
    if policy in {"lru", "hotness", "srmic"}:
        _validate_monotonicity(df)
    
    return df, trace

def replay_trace_through_sim(trace: List[Dict[str, Any]], hrm_budgets_gb: List[float], policy: str = "srmic") -> pd.DataFrame:
    """
    Utility for replaying an existing trace (e.g. synthetic).
    """
    results = _replay_trace(trace, hrm_budgets_gb, policy)
    df = pd.DataFrame(results)
    if policy in {"lru", "hotness", "srmic"}:
        _validate_monotonicity(df)
    return df

def _replay_trace(trace: List[Dict[str, Any]], hrm_budgets_gb: List[float], policy: str) -> List[Dict[str, Any]]:
    results = []
    
    # Compute total working set (unique tensors in entire trace)
    unique_tensors_all = {t['tensor_name']: t['size_bytes'] for t in trace}
    total_model_bytes = sum(unique_tensors_all.values())
    total_model_tb = total_model_bytes / (1024**4)
    
    # Compute average active working set per token
    token_to_tensors = defaultdict(set)
    tensor_name_to_size = {}
    for t in trace:
        token_to_tensors[t['token_idx']].add(t['tensor_name'])
        tensor_name_to_size[t['tensor_name']] = t['size_bytes']
    
    per_token_working_set_bytes = []
    for token_idx in token_to_tensors:
        token_bytes = sum(tensor_name_to_size[name] for name in token_to_tensors[token_idx])
        per_token_working_set_bytes.append(token_bytes)
    
    avg_active_working_set_gb = (sum(per_token_working_set_bytes) / len(per_token_working_set_bytes)) / (1024**3) if per_token_working_set_bytes else 0
    
    for budget_gb in sorted(hrm_budgets_gb):
        if policy in {"lru", "hotness", "srmic"}:
            stats = _run_x1_policy(trace, budget_gb, policy)
        else:
            stats = _run_x2_policy(trace, budget_gb, policy)
        
        # Speedup Calculation
        # T_hbm = working_set / HBM_BW
        # T_hrm = (working_set * miss_rate) / HBM_BW + (working_set * hit_rate) / SRMESH_BW
        t_hbm = total_model_tb / HBM_BW_TBPS
        t_hrm = (total_model_tb * stats['miss_rate']) / HBM_BW_TBPS + \
                (total_model_tb * stats['hit_rate']) / SRMESH_BW_TBPS
        
        speedup = t_hbm / t_hrm if t_hrm > 0 else 1.0
        
        results.append({
            "hrm_budget_gb": budget_gb,
            "hit_rate": stats['hit_rate'],
            "miss_rate": stats['miss_rate'],
            "promotions": stats['promotion_count'],
            "demotions": stats['demotion_count'],
            "working_set_gb": avg_active_working_set_gb,
            "total_model_gb": total_model_bytes / (1024**3),
            "effective_bw_reduction": stats['hit_rate'] * 100.0,
            "speedup_vs_hbm": speedup,
            "policy": policy,
            "latency_proxy": stats.get("latency_proxy"),
            "replica_count": stats.get("replica_count", 0),
            "bypass_count": stats.get("bypass_count", 0),
            "remap_count": stats.get("remap_count", 0),
            "occupancy_skew": stats.get("occupancy_skew"),
        })
    return results

def _run_x1_policy(trace: List[Dict[str, Any]], budget_gb: float, policy: str) -> Dict[str, Any]:
    sim = HRMResidencySimulator(budget_gb, num_regions=NUM_REGIONS, policy=policy, page_size_mb=PAGE_SIZE_MB)
    for access in trace:
        sim.access(access['tensor_name'], access['size_bytes'], access['token_idx'])
    return sim.get_stats()


def _run_x2_policy(trace: List[Dict[str, Any]], budget_gb: float, policy: str) -> Dict[str, Any]:
    budget_bytes = int(budget_gb * 1024**3)
    per_region_bytes = max(1, budget_bytes // NUM_REGIONS)
    cfg = X2SimConfig(
        NUM_REGIONS=NUM_REGIONS,
        REGION_CAPACITY_BYTES_OVERRIDE=per_region_bytes,
        REPLICATION_ENABLED=(policy == "x2_full"),
    )
    events = [
        TraceEvent(
            decode_step=access["token_idx"],
            object_id=access["tensor_name"],
            size_bytes=access["size_bytes"],
        )
        for access in trace
    ]
    controller = (
        BaselineX1(cfg) if policy == "x1_baseline" else RICX2(cfg, x2_mode=True)
    )
    results = TraceRunner(controller).run(events)
    summary = X2Metrics.summarize(controller, results, policy, cfg)
    return {
        "hit_rate": summary["hit_rate"],
        "miss_rate": 1.0 - summary["hit_rate"],
        "promotion_count": results.count(AccessResult.MISS_PROMOTED),
        "demotion_count": controller.total_evictions,
        "latency_proxy": summary["latency_proxy"],
        "replica_count": summary["replica_count"],
        "bypass_count": summary["bypass_count"],
        "remap_count": summary["remap_count"],
        "occupancy_skew": summary["occupancy_skew"],
    }

def _validate_monotonicity(df: pd.DataFrame) -> None:
    """
    Validates that hit_rate increases or stays same as budget increases.
    """
    hit_rates = df['hit_rate'].tolist()
    for i in range(1, len(hit_rates)):
        if hit_rates[i] < hit_rates[i-1] - 1e-6: # Float epsilon
            print(f"WARNING: Non-monotonic hit rate detected: {hit_rates[i]} < {hit_rates[i-1]}")
