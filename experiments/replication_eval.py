import sys
import os
import pandas as pd
import json

sys.path.append(os.getcwd())

from ric_x2.types import TraceEvent
from sim_x2.config import X2SimConfig
from sim_x2.baseline_x1 import BaselineX1
from ric_x2.controller import RICX2
from sim_x2.trace_runner import TraceRunner
from telemetry.metrics import X2Metrics
from experiments.stress_traces import generate_hotspot_fanout, generate_burst_contention, generate_hotset_rotation

def run_workload(trace, workload_name, cfg):
    print(f"-> Evaluating Workload: {workload_name}")
    results = []
    
    # 1. Baseline X1
    x1 = BaselineX1(cfg)
    summary_x1 = X2Metrics.summarize(x1, TraceRunner(x1).run(trace), "X1", cfg, workload_name)
    results.append(summary_x1)
    
    # 2. X2 Remap+Admission
    cfg_adm = X2SimConfig(REGION_CAPACITY_MB=cfg.REGION_CAPACITY_MB, REPLICATION_ENABLED=False)
    x2_adm = RICX2(cfg_adm, x2_mode=True)
    summary_adm = X2Metrics.summarize(x2_adm, TraceRunner(x2_adm).run(trace), "X2_Adm", cfg_adm, workload_name)
    results.append(summary_adm)
    
    # 3. X2 Full (Replicated)
    cfg_rep = X2SimConfig(REGION_CAPACITY_MB=cfg.REGION_CAPACITY_MB, REPLICATION_ENABLED=True)
    x2_rep = RICX2(cfg_rep, x2_mode=True)
    summary_rep = X2Metrics.summarize(x2_rep, TraceRunner(x2_rep).run(trace), "X2_Full", cfg_rep, workload_name)
    results.append(summary_rep)
    
    return results

def main():
    # Model size 512MB, total SRAM capacity 256MB (2x over-subscribed)
    # Each region (4MB) can hold exactly 2 tensors (~2MB each)
    cfg = X2SimConfig(
        REGION_CAPACITY_MB=4, 
        HOT_OBJECT_ACCESS_THRESHOLD=5,
        REPLICATION_PRESSURE_THRESHOLD=0.1
    )
    all_results = []
    
    # Stress traces with 512MB model (tensors ~2MB)
    all_results.extend(run_workload(generate_hotspot_fanout(model_mb=512), "HOTSPOT_FANOUT", cfg))
    all_results.extend(run_workload(generate_burst_contention(model_mb=512), "BURST_CONTENTION", cfg))
    all_results.extend(run_workload(generate_hotset_rotation(model_mb=512), "HOTSET_ROTATION", cfg))
    
    df = pd.DataFrame(all_results)
    
    # Pivot for clean comparison
    pivot_df = df.pivot(index='workload', columns='label', values='latency_proxy')
    print("\n" + "="*80)
    print("REPLICATION EVALUATION: LATENCY PROXY COMPARISON")
    print("="*80)
    print(pivot_df)
    
    # Detail Table
    print("\n" + "="*160)
    print("DETAILED METRICS")
    print("="*160)
    print(df.to_string(index=False))
    
    out_dir = "results/x2_stress_test"
    os.makedirs(out_dir, exist_ok=True)
    df.to_csv(f"{out_dir}/stress_results.csv", index=False)
    print(f"\nResults written to {out_dir}/")

if __name__ == "__main__":
    main()
