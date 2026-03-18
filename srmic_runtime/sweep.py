import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from typing import List, Dict, Any, Tuple
import pandas as pd
from .tracer import WeightAccessTracer
from .residency_sim import HRMResidencySimulator

# KEY ARCHITECTURAL CONSTANTS (from SRMIC-X1 spec)
HBM_BW_TBPS = 24.0      # TB/s aggregate
SRMESH_BW_TBPS = 96.0   # TB/s aggregate  
NUM_REGIONS = 64        # logical HRM regions (flagship)
PAGE_SIZE_MB = 2        # default page size

def run_sweep(model_name: str, prompt: str, hrm_budgets_gb: List[float], num_tokens: int = 50, policy: str = "srmic") -> Tuple[pd.DataFrame, List[Dict[str, Any]]]:
    """
    Runs inference with the tracer active, then replays the access trace through 
    the residency simulator at multiple HRM budget points.
    """
    # 1. Load Model and Trace
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float16, device_map="cpu")
    
    tracer = WeightAccessTracer()
    tracer.attach(model)
    
    input_ids = tokenizer.encode(prompt, return_tensors="pt")
    
    print(f"Tracing {num_tokens} decode steps for {model_name}...")
    with torch.no_grad():
        current_ids = input_ids
        for _ in range(num_tokens):
            outputs = model(current_ids)
            next_token_id = torch.argmax(outputs.logits[:, -1, :], dim=-1).unsqueeze(-1)
            current_ids = torch.cat([current_ids, next_token_id], dim=-1)
            tracer.step()
            
    trace = tracer.get_trace()
    tracer.detach()
    
    # 2. Replay Trace and Compute Metrics
    results = _replay_trace(trace, hrm_budgets_gb, policy)
    
    # 3. Monotonicity Validation
    df = pd.DataFrame(results)
    _validate_monotonicity(df)
    
    return df, trace

def replay_trace_through_sim(trace: List[Dict[str, Any]], hrm_budgets_gb: List[float], policy: str = "srmic") -> pd.DataFrame:
    """
    Utility for replaying an existing trace (e.g. synthetic).
    """
    results = _replay_trace(trace, hrm_budgets_gb, policy)
    df = pd.DataFrame(results)
    _validate_monotonicity(df)
    return df

def _replay_trace(trace: List[Dict[str, Any]], hrm_budgets_gb: List[float], policy: str) -> List[Dict[str, Any]]:
    results = []
    
    # Compute working set size for speedup calculation
    unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
    working_set_bytes = sum(unique_tensors.values())
    working_set_tb = working_set_bytes / (1024**4)
    
    for budget_gb in sorted(hrm_budgets_gb):
        sim = HRMResidencySimulator(budget_gb, num_regions=NUM_REGIONS, policy=policy, page_size_mb=PAGE_SIZE_MB)
        for access in trace:
            sim.access(access['tensor_name'], access['size_bytes'], access['token_idx'])
            
        stats = sim.get_stats()
        
        # Speedup Calculation
        # T_hbm = working_set / HBM_BW
        # T_hrm = (working_set * miss_rate) / HBM_BW + (working_set * hit_rate) / SRMESH_BW
        t_hbm = working_set_tb / HBM_BW_TBPS
        t_hrm = (working_set_tb * stats['miss_rate']) / HBM_BW_TBPS + \
                (working_set_tb * stats['hit_rate']) / SRMESH_BW_TBPS
        
        speedup = t_hbm / t_hrm if t_hrm > 0 else 1.0
        
        results.append({
            "hrm_budget_gb": budget_gb,
            "hit_rate": stats['hit_rate'],
            "miss_rate": stats['miss_rate'],
            "promotions": stats['promotion_count'],
            "demotions": stats['demotion_count'],
            "working_set_gb": stats['working_set_size_gb'],
            "effective_bw_reduction": stats['hit_rate'] * 100.0,
            "speedup_vs_hbm": speedup
        })
    return results

def _validate_monotonicity(df: pd.DataFrame) -> None:
    """
    Validates that hit_rate increases or stays same as budget increases.
    """
    hit_rates = df['hit_rate'].tolist()
    for i in range(1, len(hit_rates)):
        if hit_rates[i] < hit_rates[i-1] - 1e-6: # Float epsilon
            print(f"WARNING: Non-monotonic hit rate detected: {hit_rates[i]} < {hit_rates[i-1]}")
