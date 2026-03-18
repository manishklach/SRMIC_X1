# SRMIC-X2 Microarchitecture: Collision-Aware Residency Control

## 1. Overview
The SRMIC-X2 architecture addresses the **Regional Collision Ceiling** identified in X1. While X1 relies on a purely mathematical hashing function to distribute weights across regions, X2 introduces a **Control Plane** that dynamically remaps tensors to minimize thrashing.

## 2. RIC-X2 Control Plane
The Residency Intelligence Controller (RIC-X2) operates in two tiers:

### 2.1 Fast Path (Cycle-Accurate Routing)
- **Remap CAM (Content Addressable Memory):** A small associative table providing region overrides for "hot" or "colliding" tensors.
- **Hybrid Mux:** Parallel lookup between the static hash and the Remap CAM. If the CAM hits, the remapped region is used.

### 2.2 Slow Path (Policy Engine)
- **Occupancy Skew Monitor:** Calculates the standard deviation of load across all 64 regions.
- **Reactive Remapping:** If a region exceeds an occupancy threshold (e.g., 90%) and experiences a miss, the RIC identifies the "coldest" region and binds the incoming tensor to it via the Remap CAM.

## 3. Key Algorithms (MVP)

### 3.1 Reactive Remapping
```python
if current_region.occupancy > THRESHOLD:
    target = find_min_occupancy_region()
    RemapCAM.bind(tensor_id, target)
```

### 3.2 Thrash Detection
Tracks re-accesses of tensors evicted within a fixed token window. High thrash signals structural collision, escalating the remap priority for the affected tensors.

## 4. Hardware Realization
In silicon, the Remap CAM is implemented as a 256-entry register-file adjacent to the hash logic. Telemetry counters (hits/misses/occupancy) are read by a management micro-core (firmware) which performs the slow-path remapping updates.

## 5. Metrics for Validation
- **Occupancy Skew ($\sigma$):** Primary metric for load balance.
- **Useful Hit Rate:** Effectiveness of residency.
- **Remap Rate:** Control plane overhead proxy.
