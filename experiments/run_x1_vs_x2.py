import sys
import os
import pandas as pd
import json

# Add current directory to path
sys.path.append(os.getcwd())

from ric_x2.types import TraceEvent
from sim_x2.config import X2SimConfig
from sim_x2.baseline_x1 import BaselineX1
from ric_x2.controller import RICX2
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

def generate_hot_trace(steps=20, model_mb=2048):
    """Synthetic trace with high contention on few regions."""
    trace = []
    # 32 layers, each with 8 tensors
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    for s in range(steps):
        for l in range(32):
            for t in range(8):
                trace.append(TraceEvent(s, f"L{l}_T{t}", tensor_size, l))
    return trace

def main():
    cfg = X2SimConfig(REGION_CAPACITY_MB=64)
    trace = generate_hot_trace()
    
    print("Starting SRMIC-X2 MVP Experiment...")
    
    experiment_results = []

    # Run X1
    print("Running X1 Baseline...")
    x1 = BaselineX1(cfg)
    res_x1 = TraceRunner(x1).run(trace)
    experiment_results.append(X2Metrics.summarize(x1, res_x1, "X1_Baseline", cfg))
    
    # Run X2 Conservative
    print("Running X2 Conservative Remap...")
    x2_cons = RICX2(cfg, x2_mode=True)
    res_x2_cons = TraceRunner(x2_cons).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_cons, res_x2_cons, "X2_Cons_0.90", cfg))

    # Run X2 Aggressive
    print("Running X2 Aggressive Remap...")
    cfg_aggr = X2SimConfig(REGION_CAPACITY_MB=64, REMAP_OCC_THRESHOLD=0.70)
    x2_aggr = RICX2(cfg_aggr, x2_mode=True)
    res_x2_aggr = TraceRunner(x2_aggr).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_aggr, res_x2_aggr, "X2_Aggr_0.70", cfg_aggr))
    
    df = pd.DataFrame(experiment_results)
    print("\n" + "="*60)
    print("SRMIC-X2 MVP EXPERIMENT SUMMARY")
    print("="*60)
    print(df.to_string(index=False))
    print("="*60)
    
    os.makedirs("results/x2_mvp", exist_ok=True)
    df.to_csv("results/x2_mvp/mvp_results.csv", index=False)
    with open("results/x2_mvp/mvp_results.json", "w") as f:
        f.write(df.to_json(orient="records"))

if __name__ == "__main__":
    main()
