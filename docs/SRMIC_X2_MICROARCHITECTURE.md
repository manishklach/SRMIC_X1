# SRMIC-X2 Microarchitecture: Collision-Aware Residency Control (MVP)

## 1. Objective: Breaking the Collision Ceiling
The SRMIC-X1 architecture relies on a purely mathematical hashing function to distribute model weights across 64 independent HRM regions. While computationally efficient, this static mapping results in **Regional Hash Collisions**: multiple large tensors (specifically MLP weights) often hash to the same subset of regions, causing localized thrashing and capping aggregate hit rates at ~65% for dense models.

SRMIC-X2 introduces a dynamic **Control Plane** to load-balance the HRM tier without requiring a centralized, high-latency memory directory.

## 2. X2 MVP Scope: Reactive Remapping
The X2 MVP focuses exclusively on **Reactive Remapping**. It implements a software-modeled hardware **Remap CAM** (Content Addressable Memory) that provides surgical overrides to the default static hash.

### Key Logic Tiers:
- **Fast Path (Cycle-Accurate):** Parallel lookup of Static Hash and Remap CAM. $R_{target} = CAM.lookup(ID) ?? Hash(ID) \pmod{64}$.
- **Slow Path (Policy Engine):** Periodically analyzes telemetry to update the CAM and resolve hotspots.

## 3. Remap-Only Policy
The MVP implements a **Reactive Occupancy-Triggered Remapping** policy:
1. **Trigger:** A miss occurs in a region where `occupancy_fraction > REMAP_OCC_THRESHOLD`.
2. **Detection:** The RIC identifies the requested tensor as a candidate for relocation.
3. **Targeting:** The RIC queries the global `OccupancyTracker` to find the "coldest" region (minimum `used_bytes`).
4. **Binding:** A new entry is inserted into the Remap CAM, redirecting all future accesses of this tensor to the new region.
5. **Stability:** A per-object `REMAP_COOLDOWN_STEPS` prevents rapid oscillation between regions.

## 4. Simulator Flow
The X2 simulation loop executes the following per trace event:
1. **Routing:** Resolve region ID via Hash + CAM lookup.
2. **Residency Check:** Verify if `object_id` exists in the target region's set.
3. **Telemetry:** Record collisions (access to populated region) and hits/misses.
4. **Thrash Detection:** Check if the object was recently evicted (within `THRASH_WINDOW`).
5. **Control Update:** If in X2 mode and occupancy threshold is breached, perform remapping and update CAM.
6. **Promotion/Eviction:** Update physical byte counters and resident object sets.

## 5. Metrics and Observability
The MVP tracks the following to quantify the "Residency Quality of Service":
- **Useful Hit Rate:** Primary performance proxy.
- **Occupancy Skew ($\sigma$):** Standard deviation of regional occupancy. Lower skew indicates better load balancing.
- **Thrash Events:** Counts re-accesses of tensors evicted within the fixed window.
- **Remap Count:** Measures control plane activity.
- **Latency Proxy:** Weighted sum of cycles (Hit=2, Promotion=6, Bypass=10).

## 6. Experiment Setup
The first validation experiment (`run_x1_vs_x2.py`) uses a synthetic trace designed to force collisions:
- **Model:** ~2GB footprint across 32 layers.
- **Scenarios:** 
    - **X1 Baseline:** CAM disabled.
    - **X2 Conservative:** Remapping triggered at 90% occupancy.
    - **X2 Aggressive:** Remapping triggered at 70% occupancy.

## 7. Known Limitations of MVP
- **Single CAM Partition:** All tensors share one 256-entry CAM.
- **Simplified Eviction:** Uses a basic FIFO-ish eviction within regions rather than full Regret-Aware LRU.
- **No Replication:** Cannot handle bandwidth-bound hotspots (only capacity-bound hotspots).

## 8. Next Feature: Eviction Regret (Admission Control)
Once the hit-rate improvement from remapping is quantified, the next logical addition is **Admission Control via Eviction Regret**. This will allow the controller to bypass HRM entirely if promoting a new tensor would evict a resident tensor with a higher "regret" score (predicted near-term utility).
