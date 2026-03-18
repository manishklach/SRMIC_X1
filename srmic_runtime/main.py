import argparse
import sys
import os
from datetime import datetime
from .sweep import run_sweep, run_synthetic_sweep
from .plotter import save_results

def main():
    parser = argparse.ArgumentParser(description="SRMIC-X1 Runtime Residency Simulator")
    parser.add_argument("--model", type=str, default="meta-llama/Llama-3.2-1B", help="HuggingFace model name")
    parser.add_argument("--prompt", type=str, default="Explain the memory wall in AI inference", help="Prompt for tracing")
    parser.add_argument("--tokens", type=int, default=50, help="Number of tokens to generate")
    parser.add_argument("--hrm-budgets", type=float, nargs="+", default=[0.5, 1, 2, 4, 7, 10, 16], help="HRM budgets in GB to sweep")
    parser.add_argument("--policy", type=str, default="srmic", choices=["lru", "hotness", "srmic"], help="Eviction policy")
    parser.add_argument("--output", type=str, default="results/", help="Output directory")
    parser.add_argument("--dry-run", action="store_true", help="Use synthetic trace for testing")
    
    args = parser.parse_args()
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    model_slug = args.model.replace("/", "_")
    output_dir = os.path.join(args.output, f"runtime_{model_slug}_{timestamp}")
    
    if args.dry_run:
        print("Starting Dry-Run with Synthetic Trace...")
        df, trace = run_synthetic_sweep(args.hrm_budgets, num_tokens=args.tokens, policy=args.policy)
        model_name = f"Synthetic-{args.model}"
    else:
        print(f"Starting Live Trace for {args.model}...")
        df, trace = run_sweep(args.model, args.prompt, args.hrm_budgets, num_tokens=args.tokens, policy=args.policy)
        model_name = args.model
        
    print(f"Sweep complete. Saving results to {output_dir}...")
    save_results(df, trace, output_dir, model_name)
    print("Done.")

if __name__ == "__main__":
    main()
