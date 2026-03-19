# SRMIC-X2 Empirical Results Summary

**Date:** March 18, 2026  
**Status:** Deterministic synthetic evaluation completed; initial real-trace validation on public OPT models  
**Baseline:** SRMIC-X1 (Static Hashing)

## 1. Executive Summary of Findings
SRMIC-X2 improves the static-hash baseline on the reference dense trace and, after policy hardening, replication is now positive across the checked-in synthetic stress suite. Initial real-trace replay on public OPT models shows the same directional result, with **Remap + Admission** consistently outperforming both the legacy `srmic` policy and the more aggressive replicated mode.

## 2. Key Performance Metrics

### A. Load Balancing (Occupancy Skew)
The primary failure mode of X1 was regional over-subscription. X2 meaningfully improves load balance on the reference trace once replication is enabled.
| Scenario | Occupancy Skew ($\sigma$) | Improvement vs Baseline |
| :--- | :---: | :---: |
| **X1 Baseline** | 0.262 | - |
| **X2 Remap + Admission** | 0.250 | 4% |
| **X2 Full (Replicated)** | **0.147** | **44%** |

### B. Thrash Mitigation (Regret-Aware Admission)
X2 uses "Eviction Regret" to deny residency to low-value incoming weights that would displace high-value residents.
- **Reference trace bypasses:** 297 bypasses over 38,400 accesses in the remap+admission and full-X2 runs.
- **Reference trace regret prevented:** 219,890 utility units in `X2_Remap_Admission`; 101,550 in `X2_Full_Replicated`.
- **Interpretation:** admission is helpful under pressure, but its utility weights are still synthetic and not yet calibrated against real decode traces.

### C. Selective Replication (Hotspot Relief)
Validated via the `HOTSPOT_FANOUT` workload (concentrated demand on 2 regions).
- **Latency Proxy Gain:** **5.7% reduction** in total cycles.
- **Replica Hit Rate:** **24.4%**. Replicas absorbed nearly a quarter of all requests, successfully offloading congested primary regions.

## 3. Workload Sensitivity Analysis
- **Reference dense trace:** `X2_Remap_Admission` improves hit rate from 98.04% to 98.54% and reduces latency proxy from 111,540 to 109,980 cycles.
- **Replication:** Still effective for static hotspots, reducing `HOTSPOT_FANOUT` latency proxy from 14,712 to 13,880 cycles.
- **Dynamic workloads:** Policy hardening changed the previous regressions into wins: `BURST_CONTENTION` improves from 7,376 to 6,676 cycles and `HOTSET_ROTATION` improves from 39,110 to 36,644 cycles.
- **Real traces:** On `facebook/opt-125m`, `x2_admission` reaches **1.71x** at 0.2 GB HRM versus **1.29x** for `srmic`; on `facebook/opt-350m`, `x2_admission` reaches **1.45x** at 0.4 GB versus **1.19x** for `srmic`.
- **Policy ranking:** Across both public real-trace runs, `x2_admission` beats `x2_full`, suggesting remap + admission is currently the strongest default story.
- **Caution:** this is now stronger than synthetic-only evidence, but still not enough for broad architecture-validation claims. More real models are needed.

---
*Results generated from the checked-in synthetic X2 experiment harnesses after determinism hardening. Real-trace validation should be completed before external publication.*
