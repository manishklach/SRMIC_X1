import argparse
import sys
import os
from datetime import datetime
from .sweep import run_sweep, replay_trace_through_sim
from .plotter import save_results
from studies.runtime.synthetic_trace import generate_synthetic_trace

def main():
    parser = argparse.ArgumentParser(description="SRMIC-X1 Runtime Residency Simulator")
    parser.add_argument("--model", type=str, default="meta-llama/Llama-3.2-1B", help="HuggingFace model name")
    parser.add_argument("--prompt", type=str, default="Explain the memory wall in AI inference", help="Prompt for tracing")
    parser.add_argument("--tokens", type=int, default=100, help="Number of tokens to generate")
    parser.add_argument("--hrm-budgets", type=float, nargs="+", default=[0.5, 1, 2, 4, 7, 10, 16], help="HRM budgets in GB to sweep")
    parser.add_argument("--policy", type=str, default="srmic", choices=["lru", "hotness", "srmic"], help="Eviction policy")
    parser.add_argument("--output", type=str, default="results/", help="Output directory")
    parser.add_argument("--dry-run", action="store_true", help="Use synthetic trace for testing")
    parser.add_argument("--seed", type=int, default=1234, help="Random seed for reproducibility")
    parser.add_argument("--load-in-8bit", action="store_true", help="Load model in 8-bit mode")
    parser.add_argument("--hf-token", type=str, default=None, help="HuggingFace API token")
    
    args = parser.parse_args()
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_slug = args.model.replace("/", "_").lower()
    output_dir = os.path.join(args.output, f"runtime_{model_slug}_{timestamp}")
    
    if args.dry_run:
        print("Starting Dry-Run with Synthetic Trace (Llama-3-8B pattern)...")
        trace = generate_synthetic_trace(num_tokens=args.tokens, model_type="llama-3-8b")
        df = replay_trace_through_sim(trace, args.hrm_budgets, policy=args.policy)
        model_name = f"Synthetic-Llama-3-8B"
    else:
        print(f"Starting Live Trace for {args.model}...")
        df, trace = run_sweep(
            args.model, 
            args.prompt, 
            args.hrm_budgets, 
            num_tokens=args.tokens, 
            policy=args.policy,
            seed=args.seed,
            load_in_8bit=args.load_in_8bit,
            hf_token=args.hf_token
        )
        model_name = args.model
        
    # --- Print Terminal Summary ---
    avg_working_set = df['working_set_gb'].mean()
    # Unique tensors as heuristic for model size
    unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
    total_model_size_gb = sum(unique_tensors.values()) / (1024**3)
    active_frac_pct = (avg_working_set / total_model_size_gb) * 100 if total_model_size_gb > 0 else 0

    print(f"\nModel: {model_name} ({total_model_size_gb:.2f} GB)")
    print(f"Active working set: {avg_working_set:.2f} GB per token ({active_frac_pct:.1f}% of model)\n")
    print(f"{'HRM Budget':<12} | {'Hit Rate':<10} | {'Speedup':<10}")
    print("-" * 38)
    
    for _, row in df.iterrows():
        marker = " <- saturation point" if row['hit_rate'] > 0.75 and row['hrm_budget_gb'] <= 10 else "" # Heuristic
        print(f"{row['hrm_budget_gb']:>4.1f} GB     |   {row['hit_rate']*100:>3.0f}%    |  {row['speedup_vs_hbm']:>5.2f}x{marker}")

    # Invariant check for terminal
    peak_speedup = df['speedup_vs_hbm'].max()
    optimal_row = df[df['speedup_vs_hbm'] >= 0.99 * peak_speedup].iloc[0]
    inv_val = "VALIDATED" if (optimal_row['hit_rate'] > 0.70 and optimal_row['speedup_vs_hbm'] > 1.5) else "FAILED"
    print(f"\nInvariant I1+I2: {inv_val}")
    
    print(f"Results saved to: {output_dir}/")
    
    save_results(df, trace, output_dir, model_name)

if __name__ == "__main__":
    main()
