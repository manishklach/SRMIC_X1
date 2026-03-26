---
layout: default
title: Performance Evaluation | SRMIC Results
---

# Performance Evaluation

The SRMIC architecture has been evaluated using a trace-driven analytical simulation framework. This environment replays memory access patterns from mainstream LLMs—including Mistral-7B, OPT, and Qwen—to estimate the latency impact of distributed SRAM residency. 

By modeling the bandwidth ratios between HRM and HBM tiers, we can project the potential speedup of token-to-token generation steps under various hardware configurations.

## 1. Load Balancing and Skew Reduction
A primary objective of the SRMIC-X2 intelligence tier is to mitigate regional load imbalance. In the static baseline (SRMIC-X1), hash collisions lead to over-subscription of specific SRAM regions. The RIC-X2 intelligence layer significantly reduces this occupancy skew, ensuring that the aggregate bandwidth of the mesh is utilized more effectively.

| Scenario | Occupancy Skew ($\sigma$) | Improvement vs. Baseline |
| :--- | :---: | :---: |
| **SRMIC-X1 (Static Hashing)** | 0.262 | — |
| **SRMIC-X2 (Remap + Admission)** | 0.250 | 4% |
| **SRMIC-X2 Full (Replicated)** | **0.147** | **44%** |

## 2. Modeled Latency Speedup
Evaluation on the reference trace demonstrates that SRMIC-X2 maintains high hit rates even as the model working set approaches the limits of HRM capacity. This stability is critical for real-world serving, where unpredictable jitter in token generation can degrade user experience.

<div class="figure">
  <img src="{{ '/assets/images/results/opt_6_7b/runtime_facebook_opt-6.7b_20260318_002241/speedup.png' | relative_url }}" alt="OPT-6.7B Speedup Curves">
  <p class="figcaption">Figure 2: Analytical speedup projection for OPT-6.7B. The X2 policies consistently outperform the static-hash baseline by optimizing regional placement.</p>
</div>

## 3. Real-Trace Validation Summary
Analytical projections across different model families indicate consistent directional gains. These results suggest that intelligence-first residency control is a robust multiplier for raw memory bandwidth.

*   **OPT-125M:** Projected **1.71x speedup** with 0.2 GB HRM (vs 1.29x for baseline).
*   **OPT-6.7B:** Demonstrated stable speedups as the model working set expands.
*   **Qwen-2.5-1.5B:** Projected **1.17x speedup** with 0.8 GB HRM (vs 1.09x for baseline).

## 4. Throughput Scaling Analysis
In scenarios with highly asymmetric access density (e.g., concentrated demand on specific attention projection weights), selective replication acts as a "relief valve," preventing localized bandwidth saturation from bottlenecking the entire compute cluster.

<div class="figure">
  <img src="{{ '/assets/images/studies/7b/7b_throughput_vs_hrm.png' | relative_url }}" alt="Throughput Scaling">
  <p class="figcaption">Figure 3: Throughput scaling for 7B parameter models. SRMIC-X2 provides predictable performance improvements across the modeled HRM capacity sweep.</p>
</div>

### Key Analytical Takeaways
1.  **Effective Load Balancing:** Eliminating regional hotspots is the most significant contributor to performance stability.
2.  **Residency Protection:** Utility-gated admission ensures that high-value model weights are not evicted by transient cold weights.
3.  **Architectural Robustness:** The residency-first approach maintains its performance advantage across multiple model families and parameter counts.

[View Technical Artifacts →]({{ '/artifacts/' | relative_url }})
