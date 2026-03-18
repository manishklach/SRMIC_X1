import sys
import os
import pandas as pd
import json

# Add current directory to path to resolve srmic_x2 package
sys.path.append(os.getcwd())

from ric_x2.types import TraceEvent
from sim_x2.config import X2SimConfig
from sim_x2.baseline_x1 import BaselineX1
from ric_x2.controller import RICX2
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics

def generate_hot_trace(steps=50, model_mb=2048):
    """Synthetic trace with consistent patterns to observe remapping and admission benefits."""
    trace = []
    # 32 layers, 8 tensors per layer
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    for s in range(steps):
        for l in range(32):
            for t in range(8):
                trace.append(TraceEvent(
                    decode_step=s, 
                    object_id=f"L{l}_T{t}", 
                    size_bytes=tensor_size, 
                    layer_idx=l
                ))
    return trace

def validate_baseline(summary):
    """Fails the experiment if X1 baseline contains X2 metric leakage."""
    leakage_detected = False
    critical_metrics = ['bypass_rate', 'bypass_count', 'regret_prevented']
    
    for metric in critical_metrics:
        if summary.get(metric, 0) != 0:
            print(f"CRITICAL ERROR: Metric leakage in X1 Baseline! {metric} = {summary[metric]}")
            leakage_detected = True
            
    if leakage_detected:
        sys.exit(1)

def main():
    # Use small regions to force collisions and trigger remapping/admission
    cfg = X2SimConfig(REGION_CAPACITY_MB=64)
    trace = generate_hot_trace()
    
    print(f"SRMIC-X2 MVP + Admission: Running experiment over {len(trace)} events...")
    experiment_results = []

    # Scenario 1: X1 Baseline (Should have 0 admission metrics)
    print("-> Running X1 Baseline...")
    x1 = BaselineX1(cfg)
    res_x1 = TraceRunner(x1).run(trace)
    summary_x1 = X2Metrics.summarize(x1, res_x1, "X1_Baseline", cfg)
    validate_baseline(summary_x1)
    experiment_results.append(summary_x1)
    
    # Scenario 2: X2 Remap Only
    print("-> Running X2 Remap Only...")
    cfg_remap = X2SimConfig(REGION_CAPACITY_MB=64, ADMISSION_ENABLED=False)
    x2_remap = RICX2(cfg_remap, x2_mode=True)
    res_remap = TraceRunner(x2_remap).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_remap, res_remap, "X2_Remap_Only", cfg_remap))

    # Scenario 3: X2 Full (Conservative)
    print("-> Running X2 Full (Cons. Regret 10.0)...")
    cfg_cons = X2SimConfig(REGION_CAPACITY_MB=64, REGRET_THRESHOLD=10.0)
    x2_cons = RICX2(cfg_cons, x2_mode=True)
    res_cons = TraceRunner(x2_cons).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_cons, res_cons, "X2_Full_Cons_10.0", cfg_cons))

    # Scenario 4: X2 Full (Aggressive)
    print("-> Running X2 Full (Aggr. Regret 2.0)...")
    cfg_aggr = X2SimConfig(REGION_CAPACITY_MB=64, REGRET_THRESHOLD=2.0)
    x2_aggr = RICX2(cfg_aggr, x2_mode=True)
    res_aggr = TraceRunner(x2_aggr).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_aggr, res_aggr, "X2_Full_Aggr_2.0", cfg_aggr))
    
    # Process and Save
    df = pd.DataFrame(experiment_results)
    print("\n" + "="*100)
    print("SRMIC-X2 EXPERIMENT SUMMARY")
    print("="*100)
    print(df.to_string(index=False))
    print("="*100)
    
    out_dir = "results/x2_admission"
    os.makedirs(out_dir, exist_ok=True)
    df.to_csv(f"{out_dir}/admission_results.csv", index=False)
    with open(f"{out_dir}/admission_results.json", "w") as f:
        json.dump(df.to_dict(orient="records"), f, indent=4)
    
    print(f"Results written to {out_dir}/")

if __name__ == "__main__":
    main()
