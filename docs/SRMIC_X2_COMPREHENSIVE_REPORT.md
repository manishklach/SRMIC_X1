# SRMIC-X2: Comprehensive Architecture and Evaluation Report

**Date:** March 18, 2026  
**Status:** Deterministic synthetic evaluation complete; initial real-trace validation completed on public OPT models through 1.3B  
**Version:** 3.0.0 (X2 Milestone)

---

## 1. Executive Summary
The SRMIC-X2 architecture represents a major advancement in residency-first inference acceleration. By introducing a dynamic **Intelligence Layer** (RIC-X2) atop the static hardware fabric of X1, we have successfully addressed the "Collision Ceiling" that previously limited distributed SRAM tiers. 

The current branch supports three defensible claims. First, on the reference dense synthetic trace, **Remap + Admission** improves hit rate and lowers the latency proxy relative to X1. Second, on the dedicated `HOTSPOT_FANOUT` workload, **Selective Replication** reduces latency by **5.7%** and absorbs **24.4%** of accesses through replicas. Third, on initial real-trace replay using public `OPT-125m`, `OPT-350m`, and `OPT-1.3b`, **Remap + Admission** consistently outperforms both the legacy `srmic` policy and the more aggressive replicated mode.

---

## 2. The Problem: The Collision Ceiling
SRMIC-X1 identified that a distributed regional HRM tier can mitigate HBM pressure. However, static hashing policies cause multiple large tensors (e.g., MLP weights) to hash into the same subset of regions.

### [DIAGRAM] Regional Hash Collision (X1 Baseline)
```text
Region 0 [████████████] 100% (THRASHING: MLP_1, MLP_2, MLP_3)
Region 1 [            ] 0%   (IDLE)
Region 2 [████████████] 100% (THRASHING: MLP_4, MLP_5)
Region 3 [            ] 0%   (IDLE)
...
Aggregate Hit Rate capped at ~65% due to regional hotspots.
```

---

## 3. SRMIC-X2 Solution: The 3-Tier Intelligence Layer

SRMIC-X2 upgrades the Residency Intelligence Controller (RIC) with three collaborative mechanisms.

### 3.1 Tier 1: Reactive Remapping (Collision Avoidance)
Uses a 256-entry hardware-proxy **Remap CAM** to surgically override static hash results. When a region is congested, the RIC rebinds hot tensors to the coldest available regions.

### 3.2 Tier 2: Regret-Aware Admission (Pollution Protection)
Estimates the **Utility** of resident victims vs. incoming data. If the "Regret Gap" is too high, it bypasses SRAM to protect high-value residency.

### 3.3 Tier 3: Selective Hot-Object Replication (Bandwidth Relief)
Clones ultra-hot tensors into alternate regions to relieve bandwidth hotspots and provide pressure-aware routing.

### [DIAGRAM] RIC-X2 Controller Architecture
```text
      +-----------------------------------------------------------+
      |          RIC-X2 (Residency Intelligence Controller)       |
      |                                                           |
      |  +----------------+   +----------------+   +-----------+  |
      |  | Remap Engine   |   | Admission Ctrl |   | Repl. Mgr |  |
      |  | (256-entry CAM)|   | (Utility Gate) |   | (Cloning) |  |
      |  +--------+-------+   +--------+-------+   +-----+-----+  |
      |           |                    |                 |        |
      |  +--------v--------------------v-----------------v-----+  |
      |  |                 Control Logic Tier                  |  |
      |  |  (Telemetry Monitor, Skew Analytics, Regret Score)  |  |
      |  +--------------------------+--------------------------+  |
      +-----------------------------|-----------------------------+
                                    | (Remap Updates, Pins, Clones)
      +-----------------------------v-----------------------------+
      |                      HRM SRAM Tier                        |
      |  (64 Regions, 96 TB/s SRMESH, Collision-Aware Routing)    |
      +-----------------------------------------------------------+
```

---

## 4. Empirical Performance Results

### 4.1 Global Scaling Results (Reference Trace)
Evaluated on a 38,400-event trace simulating dense model decode steps.

| Metric | X1 Baseline | X2 Remap+Admission | **X2 Full (Replicated)** | Improvement |
| :--- | :---: | :---: | :---: | :---: |
| **Useful Hit Rate** | 98.04% | 98.54% | **98.54%** | +0.50 pts |
| **Occupancy Skew ($\sigma$)** | 0.262 | 0.250 | **0.147** | **44% Skew Reduction** |
| **Latency Proxy (Cycles)** | 111,540 | 109,980 | **94,550** | Best case on this trace |
| **Regret Prevented** | 0 | 219,890 | **101,550** | Synthetic utility units |
| **Replica Count** | 0 | 0 | **64** | - |

The reference trace remains synthetic and dense. These numbers are now deterministic across `PYTHONHASHSEED` values after hardening the simulator, but they should still be treated as pre-publication evidence until replicated on real decode traces.

### 4.2 Stress-Test Results: Hotspot Mitigation
Evaluated via the `HOTSPOT_FANOUT` workload (concentrated demand on 2 regions).

| Metric | X1 / X2_Adm Baseline | **X2 Full (Replicated)** | Benefit |
| :--- | :---: | :---: | :---: |
| **Latency Proxy (Cycles)** | 14,712 | **13,880** | **5.7% Latency Gain** |
| **Congestion Penalty** | 4,176 | **3,344** | **20% Congestion Relief** |
| **Replica Hit Rate** | 0.0% | **24.4%** | - |

### 4.3 Stress-Test Results: Dynamic Workload Response
After hardening the replication controller with minimum-step gating and idle-replica retirement, the branch no longer regresses on the checked-in dynamic workloads.

| Workload | X1 Latency Proxy | X2_Adm Latency Proxy | X2_Full Latency Proxy | Takeaway |
| :--- | :---: | :---: | :---: | :--- |
| **BURST_CONTENTION** | 7,376 | 7,376 | **6,676** | Replication now helps without admission bypasses |
| **HOTSET_ROTATION** | 39,110 | 40,112 | **36,644** | Replica retirement prevents stale phases from poisoning capacity |

This substantially improves the branch’s internal consistency, but the next open issue is external validity: all of these workloads remain synthetic and should be backed by real decode traces before the policy is treated as production-ready.

### 4.4 Initial Real-Trace Results: Public OPT Models
The runtime replay path now supports direct policy comparison on captured decode traces. Three public OPT models were evaluated as an initial check.

| Model | HRM Budget | `srmic` Speedup | `x2_admission` Speedup | `x2_full` Speedup | Best Policy |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **facebook/opt-125m** | 0.2 GB | 1.29x | **1.71x** | 1.54x | Remap + Admission |
| **facebook/opt-350m** | 0.4 GB | 1.19x | **1.45x** | 1.41x | Remap + Admission |
| **facebook/opt-1.3b** | 0.8 GB | 1.04x | **1.23x** | 1.20x | Remap + Admission |

These runs are materially stronger than synthetic-only evidence because the traces are captured from real model execution. They also sharpen the current architecture story: admission and remapping are the robust core, while replication remains secondary and should not headline the design until it wins more consistently on larger traces.

---

## 5. Microarchitectural Logic Flow

### [DIAGRAM] Per-Access Decision Path
```text
          [ Start: Tensor Access Request ]
                      |
            +---------v---------+
            | 1. Parallel Route |<--- [ Remap CAM ]
            | (Hash vs CAM)     |
            +---------+---------+
                      | (Target Region ID)
            +---------v---------+
            | 2. Check Residency|
            | (Primary + Replicas)|
            +---------+---------+
             /        |        \
      (Hit) /         | (Miss)  \ (Hit Replica)
     +-----v---+      |      +---v-------+
     |   HIT   |      |      | HIT_REPL  |
     +---------+      |      +-----------+
                      |
            +---------v---------+
            | 3. Utility Gate   |
            | (Regret Check)    |
            +---------+---------+
             /        |        \
    (Bypass)/         | (Admit) \ (Remap Trigger)
    +------v---+      |      +---v-------+
    | BYPASS   |      |      | REMAP/PROM|
    | (HBM)    |      |      | (SRAM)    |
    +----------+      |      +-----------+
                      |
            [ 4. Evict & Promote ]
```

---

## 6. Intellectual Property & Strategic Moat
SRMIC-X2 represents a critical defensive IP barrier. Competitors can build wide SRAM meshes, but efficiently managing the "Residency QoS" is the primary bottleneck.

### Primary Patentable Pillars:
1.  **Hybrid Mapping Elasticity:** The unique combination of static hashing + surgical hardware CAM overrides.
2.  **Regret-Aware Admission Logic:** Hardware-level protection of "hot" resident sets via pre-promotion utility analysis.
3.  **Pressure-Aware Replica Routing:** Multi-copy residency management in a distributed 2.5D/3D memory tier.

---

## 7. Conclusion and Next Steps
SRMIC-X2 moves residency acceleration from a conceptual concept to a stronger controller prototype, but not yet to a fully validated microarchitecture. The next phase should prioritize **more real-trace evaluation**, broader **policy sensitivity sweeps**, and only then **RTL hardening** of the Remap CAM and Admission logic.

**Bottom Line:** Remap plus admission now looks credible on synthetic traces and across three real public-model traces up to 1.3B. Replication is improved, but it is not yet the lead result.

---
*Report updated against deterministic branch artifacts generated on March 18, 2026.*
