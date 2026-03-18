import os
import sys
import json
import pandas as pd

# Add the root directory to path to import srmic_runtime
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from srmic_runtime.sweep import replay_trace_through_sim
from studies.runtime.synthetic_trace import generate_synthetic_trace

def main():
    hrm_budgets = [1, 4, 7, 10]
    print(f"Running CI Runtime Study with HRM budgets: {hrm_budgets}")
    
    # Generate synthetic Llama-3 8B trace
    trace = generate_synthetic_trace(num_tokens=50, model_type="llama-3-8b")
    
    # Replay through simulator
    df = replay_trace_through_sim(trace, hrm_budgets, policy="srmic")
    
    # --- Invariant Validation ---
    
    # 1. Invariant I2 Validation: Hit rate at 7GB > 0.70
    row_7gb = df[df['hrm_budget_gb'] == 7].iloc[0]
    hit_rate_7gb = row_7gb['hit_rate']
    print(f"Hit rate at 7GB: {hit_rate_7gb:.2f}")
    assert hit_rate_7gb > 0.70, f"Invariant I2 Violation: Hit rate at 7GB ({hit_rate_7gb:.2f}) < 0.70"
    
    # 2. Invariant I1+I2 Validation: Speedup at 7GB > 1.5x
    speedup_7gb = row_7gb['speedup_vs_hbm']
    print(f"Speedup at 7GB: {speedup_7gb:.2f}x")
    assert speedup_7gb > 1.5, f"Invariant I1+I2 Violation: Speedup at 7GB ({speedup_7gb:.2f}x) < 1.5x"
    
    # Save results to studies/runtime/runtime_results.json
    output_path = os.path.join(os.path.dirname(__file__), "runtime_results.json")
    results = df.to_dict(orient="records")
    with open(output_path, "w") as f:
        json.dump(results, f, indent=4)
        
    print(f"CI Runtime Study: PASS. Results saved to {output_path}")

if __name__ == "__main__":
    main()
