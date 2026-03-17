#!/usr/bin/env python3
# ============================================================================
# Performance Sweep Automation for SRMIC-X1
# ============================================================================

import os
import subprocess
import re
import csv

# Parameters to sweep
REGIONS = [4] # Keep small for prototype speed, ideally [16, 32]
DEPTHS = [32, 64]
SEEDS = [1234, 5678]

BUILD_DIR = "build"
RESULTS_FILE = os.path.join(BUILD_DIR, "perf_results.csv")
LOG_FILE = os.path.join(BUILD_DIR, "sim_results.log")

def run_sim(region, depth, seed):
    # Pass parameters via defines or plusargs (here we just use plusargs for seed and assume fixed RTL for now, 
    # but a real script would recompile. For this prototype scaffold, we will recompile).
    print(f"Sweeping: REGIONS={region}, DEPTH={depth}, SEED={seed}")
    
    # Clean obj_dir
    subprocess.run(["rm", "-rf", "build/obj_dir"], check=False)
    
    # Recompile with verilator overriding parameters
    compile_cmd = [
        "verilator", "--cc", "--assert", "-Wno-fatal", "-Mdir", "build/obj_dir",
        f"-GNUM_REGIONS={region}", f"-GREGION_DEPTH={depth}",
        "rtl/ric.sv", "rtl/hrm_region.sv", "rtl/srmesh_router.sv", "rtl/srmic_top.sv",
        "--exe", "tb/tb_top.sv", "--top-module", "srmic_top"
    ]
    subprocess.run(compile_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Build
    subprocess.run(["make", "-C", "build/obj_dir", "-j", "-f", "Vsrmic_top.mk", "Vsrmic_top"], 
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Run
    run_cmd = [f"./build/obj_dir/Vsrmic_top", f"+seed={seed}"]
    subprocess.run(run_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    # Parse results
    metrics = {"region": region, "depth": depth, "seed": seed}
    with open(LOG_FILE, "r") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=")
                metrics[k] = v
    return metrics

def main():
    os.makedirs(BUILD_DIR, exist_ok=True)
    results = []
    
    for r in REGIONS:
        for d in DEPTHS:
            for s in SEEDS:
                metrics = run_sim(r, d, s)
                results.append(metrics)
                
    # Write CSV
    if results:
        keys = results[0].keys()
        with open(RESULTS_FILE, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=keys)
            writer.writeheader()
            writer.writerows(results)
        print(f"Results written to {RESULTS_FILE}")
        
    # Generate a dummy plot script or plot if matplotlib is installed
    try:
        import matplotlib.pyplot as plt
        depths = [r['depth'] for r in results if r['seed']==1234]
        hit_rates = [float(r['hit_rate']) for r in results if r['seed']==1234]
        
        plt.figure()
        plt.plot(depths, hit_rates, marker='o')
        plt.title('HRM Hit Rate vs Region Depth')
        plt.xlabel('Region Depth (Entries)')
        plt.ylabel('Hit Rate (%)')
        plt.grid(True)
        plt.savefig(os.path.join(BUILD_DIR, "perf_plot.png"))
        print(f"Plot saved to {os.path.join(BUILD_DIR, 'perf_plot.png')}")
    except ImportError:
        print("matplotlib not installed. Skipping plot generation.")

if __name__ == "__main__":
    main()
