import torch
from transformers import AutoModelForCausalLM, AutoTokenizer
from .tracer import WeightAccessTracer
from .residency_sim import HRMResidencySimulator
import pandas as pd
import os

HBM_BW_TBPS = 24.0      # TB/s aggregate
SRMESH_BW_TBPS = 96.0   # TB/s aggregate  
NUM_REGIONS = 64        # logical HRM regions (flagship)

def run_sweep(model_name, prompt, hrm_budgets_gb, num_tokens=50, policy="srmic"):
    """
    Run inference with the tracer active, then replay the trace through the simulator.
    """
    # 1. Load Model
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModelForCausalLM.from_pretrained(model_name, torch_dtype=torch.float16, device_map="cpu")
    
    # 2. Trace Access
    tracer = WeightAccessTracer()
    tracer.attach(model)
    
    input_ids = tokenizer.encode(prompt, return_tensors="pt")
    
    # Mock generation loop to capture each step
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
    
    # 3. Replay Trace
    results = []
    
    for budget_gb in hrm_budgets_gb:
        sim = HRMResidencySimulator(budget_gb, num_regions=NUM_REGIONS, policy=policy)
        for access in trace:
            sim.access(access['tensor_name'], access['size_bytes'], access['token_idx'])
            
        stats = sim.get_stats()
        
        # Calculate speedup
        # T_hbm = working_set / HBM_BW
        # T_hrm = (working_set * miss_rate) / HBM_BW + (working_set * hit_rate) / SRMESH_BW
        # speedup = T_hbm / T_hrm
        #
        # Note: 'working_set' can be approximated as the total size of unique tensors in the trace
        unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
        working_set_bytes = sum(unique_tensors.values())
        working_set_tb = working_set_bytes / (1024**4)
        
        t_hbm = working_set_tb / HBM_BW_TBPS
        t_hrm = (working_set_tb * stats['miss_rate']) / HBM_BW_TBPS + \
                (working_set_tb * stats['hit_rate']) / SRMESH_BW_TBPS
        
        speedup = t_hbm / t_hrm if t_hrm > 0 else 1.0
        
        results.append({
            "hrm_budget_gb": budget_gb,
            "hit_rate": stats['hit_rate'],
            "miss_rate": stats['miss_rate'],
            "promotions": stats['promotions'],
            "demotions": stats['demotions'],
            "working_set_gb": working_set_bytes / (1024**3),
            "effective_bw_reduction": stats['hit_rate'] * 100.0,
            "speedup_vs_hbm": speedup
        })
        
    return pd.DataFrame(results), trace

def run_synthetic_sweep(hrm_budgets_gb, num_tokens=100, policy="srmic"):
    """
    Dry-run mode with synthetic Llama-3 8B access pattern.
    """
    # 8B model: ~32 layers, active set per layer ~125MB (total 4GB)
    num_layers = 32
    layer_size = 125 * 1024**2 # 125MB
    tensors_per_layer = 7 # q, k, v, o, up, gate, down
    
    trace = []
    for token_idx in range(num_tokens):
        for layer_idx in range(num_layers):
            for t_idx in range(tensors_per_layer):
                trace.append({
                    'token_idx': token_idx,
                    'tensor_name': f"layer_{layer_idx}_tensor_{t_idx}",
                    'size_bytes': layer_size // tensors_per_layer,
                })
                
    results = []
    for budget_gb in hrm_budgets_gb:
        sim = HRMResidencySimulator(budget_gb, num_regions=NUM_REGIONS, policy=policy)
        for access in trace:
            sim.access(access['tensor_name'], access['size_bytes'], access['token_idx'])
            
        stats = sim.get_stats()
        
        unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
        working_set_bytes = sum(unique_tensors.values())
        working_set_tb = working_set_bytes / (1024**4)
        
        t_hbm = working_set_tb / HBM_BW_TBPS
        t_hrm = (working_set_tb * stats['miss_rate']) / HBM_BW_TBPS + \
                (working_set_tb * stats['hit_rate']) / SRMESH_BW_TBPS
        
        speedup = t_hbm / t_hrm if t_hrm > 0 else 1.0
        
        results.append({
            "hrm_budget_gb": budget_gb,
            "hit_rate": stats['hit_rate'],
            "miss_rate": stats['miss_rate'],
            "promotions": stats['promotions'],
            "demotions": stats['demotions'],
            "working_set_gb": working_set_bytes / (1024**3),
            "effective_bw_reduction": stats['hit_rate'] * 100.0,
            "speedup_vs_hbm": speedup
        })
        
    return pd.DataFrame(results), trace
