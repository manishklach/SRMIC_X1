---
layout: default
title: SRMIC Benchmarks | Performance Results
---

# Performance Evaluation

The SRMIC architecture has been evaluated across synthetic stress-tests and real-trace replays for mainstream LLMs (Mistral-7B, OPT, Qwen).

## 1. Load Balancing and Skew Reduction
A primary goal of SRMIC-X2 is regional load balancing. In static hashing (SRMIC-X1), hash collisions lead to regional over-subscription. SRMIC-X2's intelligence layer significantly reduces this skew.

| Scenario | Occupancy Skew ($\sigma$) | Improvement |
| :--- | :---: | :---: |
| **SRMIC-X1 Baseline** | 0.262 | - |
| **SRMIC-X2 Remap + Admission** | 0.250 | 4% |
| **SRMIC-X2 Full (Replicated)** | **0.147** | **44%** |

## 2. Token-to-Token Latency Speedup
Evaluation on the reference trace shows that SRMIC-X2 maintains high hit rates even under high capacity pressure.

<div class="figure">
  <img src="{{ '/assets/images/results/opt_6_7b/runtime_facebook_opt-6.7b_20260318_002241/speedup.png' | relative_url }}" alt="OPT-6.7B Speedup Curves">
  <p class="figcaption">Figure 2: Latency speedup for OPT-6.7B across varying HRM capacities. X2 policies consistently outperform the static-hash baseline.</p>
</div>

## 3. Real-Trace Validation
Trace-driven simulation on public OPT and Qwen models confirms consistent gains:
*   **OPT-125M:** Achieved **1.71x speedup** with 0.2 GB HRM (vs 1.29x for baseline).
*   **OPT-6.7B:** Demonstrated stable speedups even as the model working set grows.
*   **Qwen-2.5-1.5B:** Achieved **1.17x speedup** with 0.8 GB HRM (vs 1.09x for baseline).

## 4. Selective Hot-Object Replication
In scenarios with highly asymmetric access density (e.g., concentrated demand on specific tensors), replication acts as a relief valve.

<div class="figure">
  <img src="{{ '/assets/images/studies/7b/7b_throughput_vs_hrm.png' | relative_url }}" alt="Throughput Scaling">
  <p class="figcaption">Figure 3: Throughput scaling for 7B parameter models. SRMIC-X2 provides predictable performance across the HRM capacity sweep.</p>
</div>

### Key Takeaways
1.  **Load Balance is Key:** Most performance gains come from eliminating regional hotspots.
2.  **Admission Intelligence:** Selective admission protects the SRAM tier from pollution by cold weights.
3.  **Scale and Stability:** SRMIC remains stable across model families and sizes.

[Download Technical Artifacts →]({{ '/artifacts/' | relative_url }})
