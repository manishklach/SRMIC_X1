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

def generate_hot_trace(steps=100, model_mb=2048):
    """Synthetic trace with high contention on few regions. T0 is made 'Ultra Hot'."""
    trace = []
    # 32 layers, 8 tensors per layer.
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    for s in range(steps):
        for l in range(32):
            for t in range(8):
                # Standard Access
                trace.append(TraceEvent(s, f"L{l}_T{t}", tensor_size, l))
                # T0 is accessed twice per layer to force replication-eligible hotness
                if t == 0:
                    trace.append(TraceEvent(s, f"L{l}_T{t}", tensor_size, l))
    return trace

def generate_unbalanced_trace(steps=100, model_mb=2048):
    """
    Synthetic trace with extreme hotspots. 
    T0 and T1 in each layer are accessed 5x more than others.
    """
    trace = []
    tensor_size = (model_mb * 1024 * 1024) // (32 * 8)
    for s in range(steps):
        for l in range(32):
            for t in range(8):
                # Standard access
                trace.append(TraceEvent(s, f"L{l}_T{t}", tensor_size, l))
                # Extreme hotness for specific tensors to trigger replication
                if t < 2:
                    for _ in range(4):
                        trace.append(TraceEvent(s, f"L{l}_T{t}", tensor_size, l))
    return trace

def validate_baseline(summary):
    critical_metrics = ['bypass_count', 'remap_count', 'replica_count']
    for m in critical_metrics:
        if summary.get(m, 0) != 0:
            print(f"CRITICAL ERROR: Metric leakage in Baseline! {m} = {summary[m]}")
            sys.exit(1)

def main():
    # Force replication to verify mechanism
    cfg = X2SimConfig(
        REGION_CAPACITY_MB=64, 
        HOT_OBJECT_ACCESS_THRESHOLD=1,
        REPLICATION_PRESSURE_THRESHOLD=0.0,
        REPLICATION_ENABLED=True
    )
    trace = generate_unbalanced_trace()
    print(f"SRMIC-X2 FULL: Running experiment over {len(trace)} events...")
    experiment_results = []

    # 1. X1 Baseline
    x1 = BaselineX1(cfg)
    res_x1 = TraceRunner(x1).run(trace)
    summary_x1 = X2Metrics.summarize(x1, res_x1, "X1_Baseline", cfg)
    validate_baseline(summary_x1)
    experiment_results.append(summary_x1)
    
    # 2. X2 Remap + Admission
    cfg_adm = X2SimConfig(REGION_CAPACITY_MB=64, REPLICATION_ENABLED=False)
    x2_adm = RICX2(cfg_adm, x2_mode=True)
    res_adm = TraceRunner(x2_adm).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_adm, res_adm, "X2_Remap_Admission", cfg_adm))

    # 3. X2 Full (Remap + Admission + Replication)
    cfg_full = X2SimConfig(REGION_CAPACITY_MB=64, REPLICATION_ENABLED=True)
    x2_full = RICX2(cfg_full, x2_mode=True)
    res_full = TraceRunner(x2_full).run(trace)
    experiment_results.append(X2Metrics.summarize(x2_full, res_full, "X2_Full_Replicated", cfg_full))
    
    df = pd.DataFrame(experiment_results)
    print("\n" + "="*140)
    print("SRMIC-X2 FINAL VALIDATION")
    print("="*140)
    print(df.to_string(index=False))
    print("="*140)
    
    out_dir = "results/x2_full"
    os.makedirs(out_dir, exist_ok=True)
    df.to_csv(f"{out_dir}/full_results.csv", index=False)
    with open(f"{out_dir}/full_results.json", "w") as f:
        json.dump(df.to_dict(orient="records"), f, indent=4)
    print(f"Results written to {out_dir}/")

if __name__ == "__main__":
    main()
