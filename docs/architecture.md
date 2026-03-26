---
layout: default
title: Systems Architecture | SRMIC
---

# Systems Architecture

The SRMIC architecture is an analytical framework designed to optimize Large Language Model (LLM) decode steps by introducing a distributed, on-package residency tier. By shifting the primary weight-fetch path from external HBM to a local SRAM mesh, the architecture seeks to minimize the latency variance and bandwidth constraints inherent in traditional memory hierarchies.

## 1. The Distributed Memory Model

SRMIC utilizes a **Bounded Working-Set Model**. Unlike general-purpose caches, the architecture assumes that for a given model and token-generation step, a specific, predictable subset of weights is required. This "active working set" is partitioned across multiple HRM (Hybrid Residency Memory) regions that operate independently and in parallel.

This distributed approach ensures that aggregate bandwidth scales linearly with the number of regions, providing a theoretical performance floor that is significantly higher than conventional HBM-bound paths.

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

The **RIC-X2 (Residency Intelligence Controller)** represents the logic tier of the SRMIC ecosystem. It transforms a static mesh into a dynamic system capable of real-time load balancing. Because static hashing often leads to regional hotspots—where a few SRAM regions are over-utilized while others remain idle—the RIC-X2 monitors telemetry to override placement decisions.

### Key Intelligence Mechanisms:
*   **Reactive Remapping:** Dynamically relocates colliding tensors from congested to under-utilized regions based on occupancy skew.
*   **Regret-Aware Admission:** A utility-gated mechanism that prevents transient data from displacing high-value "hot" residents.
*   **Selective Replication:** Clones ultra-hot tensors to secondary regions to alleviate localized bandwidth pressure.

## 3. High-Bandwidth Fabric (SRMESH)

The SRMESH fabric is a regional, high-bandwidth interconnect designed to keep traffic local to the tensor clusters. By minimizing global on-chip movement, the fabric reduces the energy-per-bit cost of weight fetches compared to repeated HBM transactions.

### Modeled Parameters (SRMIC-P1 Baseline)
| Parameter | Value | Rationale |
|---|---|---|
| HBM Aggregate BW | 24,000 GB/s | 8 stacks (HBM3e class) |
| SRMESH Aggregate BW | 48,000 GB/s | Regional SRAM fabric |
| HRM Regions | 16 | 4 chiplets × 4 regions |
| Tensor Clusters | 128 | 8 clusters per HRM region pair |

## 4. Formal Verification and RTL Equivalence
To ensure the analytical model is grounded in hardware feasibility, the SRMIC architecture is backed by a **Formal Specification (TLM)**. This model defines the deterministic state transitions required for residency management, allowing for future RTL-equivalence checking and ensuring that no deadlocks occur during dynamic remapping.

[View Performance Evaluation →]({{ '/results/' | relative_url }})
