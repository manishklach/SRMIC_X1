from collections import defaultdict
import matplotlib.pyplot as plt
import pandas as pd
import os
from datetime import datetime
from typing import List, Dict, Any

def save_results(df: pd.DataFrame, trace: List[Dict[str, Any]], output_dir: str, model_name: str) -> None:
    """
    Generates and saves all plots, CSV results, and the summary report.
    """
    os.makedirs(output_dir, exist_ok=True)
    
    # Save CSV
    df.to_csv(os.path.join(output_dir, "sweep_results.csv"), index=False)
    
    # --- Plotting Setup ---
    plt.style.use('seaborn-v0_8-whitegrid') # Professional look

    # 1. Hit Rate vs HRM Budget
    plt.figure(figsize=(10, 6))
    plt.plot(df['hrm_budget_gb'], df['hit_rate'] * 100, marker='o', linewidth=2, color='#2c3e50')
    plt.title(f'HRM Hit Rate vs Capacity ({model_name})', fontsize=14)
    plt.xlabel('HRM Budget (GB)', fontsize=12)
    plt.ylabel('Hit Rate (%)', fontsize=12)
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, "hrm_hit_rate.png"))
    plt.close()

    # 2. Speedup vs HRM Budget
    plt.figure(figsize=(10, 6))
    plt.plot(df['hrm_budget_gb'], df['speedup_vs_hbm'], marker='s', linewidth=2, color='#e74c3c', label='SRMIC-X1 (96 TB/s)')
    plt.axhline(y=1.0, color='black', linestyle='--', label='HBM-only Baseline (24 TB/s)')
    plt.title(f'Decode Speedup vs HRM Capacity ({model_name})', fontsize=14)
    plt.xlabel('HRM Budget (GB)', fontsize=12)
    plt.ylabel('Speedup (x)', fontsize=12)
    plt.legend()
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, "speedup.png"))
    plt.close()

    # 3. Working Set Composition
    composition = defaultdict(int)
    unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
    for name, size in unique_tensors.items():
        lname = name.lower()
        if 'attn' in lname or 'self_out' in lname or 'q_proj' in lname or 'k_proj' in lname or 'v_proj' in lname:
            composition['Attention'] += size
        elif 'mlp' in lname or 'ffn' in lname or 'gate_proj' in lname or 'up_proj' in lname or 'down_proj' in lname or 'fc1' in lname or 'fc2' in lname:
            composition['MLP'] += size
        elif 'embed' in lname:
            composition['Embeddings'] += size
        elif 'kv' in lname:
            composition['KV Cache'] += size
        else:
            composition['Other'] += size
            
    labels = list(composition.keys())
    sizes = [composition[l] for l in labels]
    
    plt.figure(figsize=(8, 8))
    plt.pie(sizes, labels=labels, autopct='%1.1f%%', startangle=140, colors=['#3498db', '#2ecc71', '#f1c40f', '#e67e22', '#95a5a6'])
    plt.title(f'Working Set Composition ({model_name})', fontsize=14)
    plt.savefig(os.path.join(output_dir, "working_set_composition.png"))
    plt.close()

    # 4. Per-token Working Set Size
    token_sizes = defaultdict(int)
    for entry in trace:
        token_sizes[entry['token_idx']] += entry['size_bytes']
    
    sorted_tokens = sorted(token_sizes.keys())
    sizes_gb = [token_sizes[t] / (1024**3) for t in sorted_tokens]
    
    plt.figure(figsize=(10, 6))
    plt.plot(sorted_tokens, sizes_gb, color='#8e44ad', linewidth=2)
    plt.title(f'Per-Token Working Set Size ({model_name})', fontsize=14)
    plt.xlabel('Token Index', fontsize=12)
    plt.ylabel('Size (GB)', fontsize=12)
    plt.grid(True, linestyle='--', alpha=0.7)
    plt.savefig(os.path.join(output_dir, "per_token_working_set.png"))
    plt.close()

    generate_summary(df, trace, model_name, output_dir, composition)

def generate_summary(df: pd.DataFrame, trace: List[Dict[str, Any]], model_name: str, output_dir: str, composition: Dict[str, int]) -> None:
    """
    Generates summary.md in the exact requested format.
    """
    num_tokens = len(set(t['token_idx'] for t in trace))
    avg_working_set_gb = df['working_set_gb'].mean()
    
    # Heuristic for full model size (total unique tensors)
    unique_tensors = {t['tensor_name']: t['size_bytes'] for t in trace}
    total_model_size_gb = sum(unique_tensors.values()) / (1024**3)
    active_frac_pct = (avg_working_set_gb / total_model_size_gb) * 100 if total_model_size_gb > 0 else 0

    # Optimal point (Diminishing returns heuristic: where speedup gain < 1%)
    peak_speedup = df['speedup_vs_hbm'].max()
    optimal_row = df[df['speedup_vs_hbm'] >= 0.99 * peak_speedup].iloc[0]
    
    # Invariant Validation
    inv_val = "YES" if (optimal_row['hit_rate'] > 0.70 and optimal_row['speedup_vs_hbm'] > 1.5) else "NO"

    comp_total = sum(composition.values())
    
    summary = f"""# SRMIC-X1 Runtime Study — {model_name}
Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Tokens generated: {num_tokens}
Full model size: {total_model_size_gb:.2f} GB

## Key Findings
- Active working set per token: {avg_working_set_gb:.2f} GB ({active_frac_pct:.1f}% of model)
- HRM hit rate at optimal budget ({optimal_row['hrm_budget_gb']:.1f} GB): {optimal_row['hit_rate']*100:.1f}%
- Speedup vs HBM-only at optimal: {optimal_row['speedup_vs_hbm']:.2f}x
- Invariant I1+I2 validated: {inv_val}

## Working Set Breakdown
- Attention weights: { (composition['Attention']/comp_total)*100:.1f}%
- MLP weights: { (composition['MLP']/comp_total)*100:.1f}%  
- KV cache: { (composition.get('KV Cache', 0)/comp_total)*100:.1f}%
- Embeddings: { (composition['Embeddings']/comp_total)*100:.1f}%

## Speedup Table
| HRM Budget (GB) | Hit Rate | Speedup vs HBM |
|-----------------|----------|----------------|
"""
    for _, row in df.iterrows():
        summary += f"| {row['hrm_budget_gb']:.1f} | {row['hit_rate']*100:.1f}% | {row['speedup_vs_hbm']:.2f}x |\n"

    summary += f"""
---
*Generated by SRMIC Runtime Simulator v2.0*
"""
    with open(os.path.join(output_dir, "summary.md"), "w") as f:
        f.write(summary)
