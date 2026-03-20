import os
import sys
import json
import pandas as pd
import argparse

# Add the root directory to path to import srmic_runtime
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../../")))

from srmic_runtime.sweep import run_sweep, replay_trace_through_sim
from studies.runtime.synthetic_trace import generate_synthetic_trace

def main():
    parser = argparse.ArgumentParser(description="SRMIC-X1 Multi-Model Comparison Study")
    parser.add_argument("--models", type=str, nargs="+", default=["meta-llama/Llama-3.2-1B"], help="List of models to compare")
    parser.add_argument("--hrm-budgets", type=float, nargs="+", default=[1, 4, 7], help="HRM budgets to test")
    parser.add_argument("--tokens", type=int, default=30, help="Tokens to generate for each model")
    parser.add_argument("--policies", type=str, nargs="+", default=["srmic"], help="Replay policies to compare")
    parser.add_argument("--output", type=str, default="studies/runtime/multi_model_comparison/", help="Output directory")
    parser.add_argument("--hf-token", type=str, default=None, help="Optional Hugging Face token for gated models")
    parser.add_argument("--trust-remote-code", action="store_true", help="Allow model/tokenizer custom code from the Hugging Face repo")
    
    args = parser.parse_args()
    
    os.makedirs(args.output, exist_ok=True)
    
    all_results = []
    
    for model_name in args.models:
        print(f"\nEvaluating Model: {model_name}")
        try:
            reference_trace = None
            for policy in args.policies:
                if reference_trace is None:
                    df, reference_trace = run_sweep(
                        model_name,
                        "Explain why transformer inference is memory bound.",
                        args.hrm_budgets,
                        num_tokens=args.tokens,
                        policy=policy,
                        hf_token=args.hf_token,
                        trust_remote_code=args.trust_remote_code,
                    )
                else:
                    df = replay_trace_through_sim(reference_trace, args.hrm_budgets, policy=policy)
                df['model'] = model_name
                all_results.append(df)
        except Exception as e:
            print(f"Error evaluating {model_name}: {e}")
            
    if not all_results:
        print("No models were successfully evaluated. Falling back to synthetic baseline for CI.")
        trace = generate_synthetic_trace(num_tokens=args.tokens, model_type="llama-3-8b")
        for policy in args.policies:
            df = replay_trace_through_sim(trace, args.hrm_budgets, policy=policy)
            df['model'] = "Synthetic-Llama-3-8B"
            all_results.append(df)

    comparison_df = pd.concat(all_results)
    
    # Generate Comparison Table
    pivot_df = comparison_df.pivot_table(index=['model', 'policy'], columns='hrm_budget_gb', values='speedup_vs_hbm')
    print("\nSpeedup Comparison Table (vs HBM-only):")
    print(pivot_df)
    
    # Save results
    output_path = os.path.join(args.output, "comparison_results.csv")
    comparison_df.to_csv(output_path, index=False)
    
    summary_path = os.path.join(args.output, "comparison_summary.json")
    comparison_df.to_json(summary_path, orient="records", indent=4)
        
    print(f"\nMulti-Model Comparison Study complete. Results saved to {args.output}")

if __name__ == "__main__":
    main()
