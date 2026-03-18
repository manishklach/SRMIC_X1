import sys
import os
import json
import pandas as pd

# Add current directory to path
sys.path.append(os.getcwd())

from sim_x2.config import X2SimConfig
from sim_x2.baseline_x1 import BaselineX1
from ric_x2.controller import RICX2
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

def generate_synthetic_trace(num_tokens: int, model_size_mb: int):
    """Generates a trace where some regions are intentionally overloaded by hashing."""
    trace = []
    # Simplified: 32 layers, each with 8 tensors
    num_layers = 32
    tensors_per_layer = 8
    tensor_size = (model_size_mb * 1024 * 1024) // (num_layers * tensors_per_layer)
    
    for t_idx in range(num_tokens):
        for l_idx in range(num_layers):
            for i in range(tensors_per_layer):
                trace.append({
                    "token_idx": t_idx,
                    "layer_idx": l_idx,
                    "tensor_id": f"L{l_idx}_T{i}",
                    "size_bytes": tensor_size
                })
    return trace

def main():
    config = X2SimConfig(REGION_CAPACITY_MB=64) # Smaller regions to force collisions
    num_tokens = 20
    model_size_mb = 2048 # ~2GB model
    
    print(f"Generating synthetic trace for {model_size_mb}MB model, {num_tokens} tokens...")
    trace = generate_synthetic_trace(num_tokens, model_size_mb)
    
    experiment_results = []

    # 1. Run X1 Baseline
    print("\nRunning X1 Baseline...")
    x1_ctrl = BaselineX1(config)
    x1_runner = TraceRunner(x1_ctrl)
    res_x1 = x1_runner.run(trace)
    experiment_results.append(X2Metrics.summarize(x1_ctrl, res_x1, "X1_Baseline"))

    # 2. Run X2 Remap-Only (Conservative)
    print("Running X2 Conservative Remap...")
    x2_cons = RICX2(config.NUM_REGIONS, config.region_capacity_bytes, config.MAX_CAM_ENTRIES, config.REMAP_COOLDOWN_TOKENS)
    runner_x2_cons = TraceRunner(x2_cons)
    res_x2_cons = runner_x2_cons.run(trace, remap_threshold=0.95)
    experiment_results.append(X2Metrics.summarize(x2_cons, res_x2_cons, "X2_Cons_0.95"))

    # 3. Run X2 Remap-Only (Aggressive)
    print("Running X2 Aggressive Remap...")
    x2_aggr = RICX2(config.NUM_REGIONS, config.region_capacity_bytes, config.MAX_CAM_ENTRIES, config.REMAP_COOLDOWN_TOKENS)
    runner_x2_aggr = TraceRunner(x2_aggr)
    res_x2_aggr = runner_x2_aggr.run(trace, remap_threshold=0.70)
    experiment_results.append(X2Metrics.summarize(x2_aggr, res_x2_aggr, "X2_Aggr_0.70"))

    # Output Results
    df = pd.DataFrame(experiment_results)
    print("\n" + "="*60)
    print("SRMIC-X2 MVP EXPERIMENT SUMMARY")
    print("="*60)
    print(df.to_string(index=False))
    print("="*60)
    
    # Save to disk
    os.makedirs("results/x2_mvp", exist_ok=True)
    df.to_csv("results/x2_mvp/x1_vs_x2_summary.csv", index=False)
    with open("results/x2_mvp/x1_vs_x2_summary.json", "w") as f:
        json.dump(experiment_results, f, indent=4)

if __name__ == "__main__":
    main()
