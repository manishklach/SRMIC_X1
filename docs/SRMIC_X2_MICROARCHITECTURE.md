# SRMIC-X2 Microarchitecture: Collision-Aware Residency Control

## 1. Objective: Breaking the Collision Ceiling
SRMIC-X1 identifies that distributed regional HRM hit rates are capped due to regional hash collisions. X2 introduces a dynamic control plane to load-balance and protect the HRM tier.

## 2. Fast Path: Hybrid Routing
- **Remap CAM:** A 256-entry associative table providing region overrides.
- **Deterministic Hashing:** MD5-based consistent mapping for the base region.

## 3. Slow Path Tier 1: Reactive Remapping
- **Policy:** Monitors regional occupancy skew. rebinds tensors to the coldest region upon detecting persistent thrashing or high-occupancy misses.

## 4. Slow Path Tier 2: Regret-Aware Admission Control
The RIC-X2 implements a "Bypass" mechanism to protect high-value residency from being polluted by low-value incoming data.

### 4.1 Motivation
In SRMIC-X1, every miss triggered a promotion. X2 evaluates the "Utility" of both the incoming object and the resident victim before permitting SRAM residency.

### 4.2 Utility Heuristic
The controller computes a utility score $U$ for each object:
$$U = w_{access} \cdot AccessCount + w_{recency} \cdot \frac{1}{1 + age} + w_{hits} \cdot HitCount - w_{thrash} \cdot ThrashCount$$

### 4.3 Bypass Decision
On a miss, if:
$$U_{victim} - U_{incoming} > \text{RegretThreshold}$$
The controller serves the request from HBM (`MISS_BYPASSED`) and preserves the resident victim. This prevents "hot" core weights from being displaced by transient data.

## 5. Selective Hot-Object Replication
Replication acts as a relief valve for bandwidth and capacity hotspots. 

### 5.1 Pressure-Aware Selection
On every access, the RIC queries the occupancy counters of all regions containing a copy of the requested object. It dynamically routes the request to the region with the lowest current utilization (`PRESSURE_AWARE_ROUTING`).

### 5.2 Empirical Validation (Stress-Test Framework)
To isolate the value of replication, we utilize specific stress-trace families:
- **HOTSPOT_FANOUT:** Small set of ultra-hot tensors (10x access density) targeting same base region.
- **BURST_CONTENTION:** Sharp spikes of high-demand concurrency.
- **HOTSET_ROTATION:** Shifting working sets to test replica stale-ness.

**Key Findings:**
- **Hotspot Relief:** In static hotspot scenarios (`HOTSPOT_FANOUT`), replication achieved a **6% reduction in latency proxy** and absorbed **~25% of all hits**, successfully flattening regional occupancy skew.
- **Capacity/Bandwidth Tradeoff:** In highly dynamic workloads, aggressive replication can dilute HRM capacity, leading to increased bypass rates and higher overall latency. This confirms replication should remain a **conservative, utility-gated mechanism**.

### 5.3 Replication Metrics
- **Replica Selected Ratio:** Frequency of choosing a replica over the primary copy.
- **Congestion Relief:** Measured as the reduction in `CONGESTION_PENALTY` cycles.
