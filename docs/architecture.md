---
layout: default
title: SRMIC Systems Architecture | SRAM-Centric Decode Acceleration
---

# Architecture Overview

The SRMIC architecture is designed to optimize LLM decode steps where a bounded working set of weights must be accessed for every token. Instead of a flat memory hierarchy, SRMIC introduces an intelligent, distributed residency tier.

## 1. The Distributed Memory Model

SRMIC uses a **Bounded Working-Set Model**. Each HRM (Hybrid Residency Memory) region operates independently and in parallel. This distributed approach ensures that aggregate bandwidth scales with the number of regions.

```text
┌─────────────────────────────────────┐
│         Tensor Inference Clusters   │
│         (Compute — memory-bound)    │
└──────────────────┬──────────────────┘
                   │
      ┌────────────┴────────────┐
      │      SRMESH Fabric      │
      │    48,000 GB/s agg.     │
      └────────────┬────────────┘
     /    /    /   │   \    \    \
  [R0] [R1] [R2] [R3] ... [R14] [R15]
   │    │    │    │           │    │
  HRM  HRM  HRM  HRM  ...   HRM  HRM
  (128 MB SRAM per region — 16 regions)
                   │
      ┌────────────┴────────────┐
      │          HBM            │
      │    24,000 GB/s agg.     │  ← cold tier / miss handler
      └─────────────────────────┘
```

## 2. Residency Intelligence (SRMIC-X2)

The **RIC-X2 (Residency Intelligence Controller)** is the core intelligence upgrade for the SRMIC ecosystem. It transforms a static mesh into an intelligent system capable of real-time load balancing and thrash mitigation.

### Key Intelligence Mechanisms:
*   **Reactive Remapping:** Dynamic relocation of colliding tensors from congested to under-utilized regions.
*   **Regret-Aware Admission:** A utility-based gate that prevents "hot" cores from being displaced by low-value transient data.
*   **Selective Replication:** Automated cloning of "ultra-hot" tensors (e.g., attention projections) to secondary regions to relieve localized bandwidth hotspots.

## 3. High-Bandwidth Fabric (SRMESH)

The SRMESH fabric is a regional, high-bandwidth interconnect that enables HRM regions to serve local partitions of active weights to adjacent tensor clusters. By keeping traffic local, SRMESH avoids the power and latency penalties of traversing global on-chip fabrics.

### Performance Parameters (SRMIC-P1)
| Parameter | Value | Rationale |
|---|---|---|
| HBM Aggregate BW | 24,000 GB/s | 8 stacks (HBM3e class) |
| SRMESH Aggregate BW | 48,000 GB/s | Local SRAM fabric |
| HRM Regions | 16 | 4 chiplets × 4 regions |
| Tensor Clusters | 128 | 8 clusters per HRM region pair |

## 4. Formal Verification
The SRMIC architecture is backed by a **Formal Specification (TLM)** that ensures deterministic behavior across distributed regions. We utilize formal properties to verify:
*   **Residency Invariants:** Ensuring tensors are only evicted under valid policy decisions.
*   **Fabric Liveness:** Guaranteeing no deadlocks during regional remapping cycles.

[View Results Summary →]({{ '/results/' | relative_url }})
