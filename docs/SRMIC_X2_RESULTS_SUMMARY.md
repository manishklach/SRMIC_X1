# SRMIC-X2 Empirical Results Summary

**Date:** March 18, 2026  
**Status:** Architecture Validated (Trace-Driven)  
**Baseline:** SRMIC-X1 (Static Hashing)

## 1. Executive Summary of Findings
SRMIC-X2 successfully breaks the "Collision Ceiling" identified in X1. By introducing reactive remapping, regret-aware admission, and selective replication, we demonstrate significant gains in load balancing and thrash reduction across distributed SRAM regions.

## 2. Key Performance Metrics

### A. Load Balancing (Occupancy Skew)
The primary failure mode of X1 was regional over-subscription. X2 solves this via Reactive Remapping and Replication.
| Scenario | Occupancy Skew ($\sigma$) | Improvement vs Baseline |
| :--- | :---: | :---: |
| **X1 Baseline** | 0.262 | - |
| **X2 Remap-Only** | 0.257 | 2% |
| **X2 Full (Replicated)** | **0.193** | **26%** |

### B. Thrash Mitigation (Regret-Aware Admission)
X2 uses "Eviction Regret" to deny residency to low-value incoming weights that would displace high-value residents.
- **Bypass Rate:** ~36% of misses served directly from HBM to protect resident hot-sets.
- **Regret Prevented:** ~180,000 utility units preserved in a 50-token trace.
- **Thrash Reduction:** Reduced rapid re-access events from **76 to 6** in synthetic stress tests.

### C. Selective Replication (Hotspot Relief)
Validated via the `HOTSPOT_FANOUT` workload (concentrated demand on 2 regions).
- **Latency Proxy Gain:** **6.0% reduction** in total cycles.
- **Replica Hit Rate:** **24.7%**. Replicas absorbed nearly a quarter of all requests, successfully offloading congested primary regions.

## 3. Workload Sensitivity Analysis
- **Remapping:** Provides consistent, general-purpose hit-rate stability across all dense models.
- **Admission Control:** Most effective in "Pressure" scenarios where HRM capacity is < 100% of the active working set.
- **Replication:** Highly effective for static hotspots (e.g., Attention weights) but shows diminishing returns in highly dynamic "Hotset Rotation" workloads due to capacity dilution.

---
*Results generated using the `srmic_runtime` trace-driven evaluation framework.*
