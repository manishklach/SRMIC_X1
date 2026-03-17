# SRMIC Architectural Invariants

The SRMIC RTL prototype explicitly enforces the following hardware invariants via SystemVerilog Assertions (SVA) and structural design.

## I1: Region Capacity Bounded
**Invariant:** A region's occupancy must never exceed its physical depth (`REGION_DEPTH`).
**Hardware Enforcement:** 
The RIC tracks true occupancy using a counter per region. Demotions are issued proactively when occupancy reaches the limit. Assertions verify `occupancy[i] <= REGION_DEPTH` and ensure `region_full` accurately reflects this state.

## I2: No Double Residency
**Invariant:** A page cannot be promoted multiple times concurrently, nor can it occupy multiple slots in the same region.
**Hardware Enforcement:**
The RIC implements a Pin Register File (CAM) that tracks inflight promotions. Any new miss for an inflight page is squashed, preventing duplicate entries in the promotion FIFO. The HRM region also asserts that no two valid entries hold the same tag.

## I3: Deterministic Victim Selection
**Invariant:** Victim selection for demotion must be deterministic, avoiding random or arbitrary eviction.
**Hardware Enforcement:**
The HRM region implements a true 3-bit LRU aging mechanism per entry. The oldest entry (or the first invalid entry) is deterministically chosen as the victim.

## I4: Bounded Working Set
**Invariant:** The architecture must constrain the active per-token working set to the available SRAM to maintain performance.
**Hardware Enforcement:**
This is a systemic invariant modeled by the Token Bucket throttle in the RIC. The architecture rate-limits promotions, ensuring the residency tier is not overwhelmed by thrashing. If the working set exceeds the HRM capacity, the architecture degrades gracefully back to HBM performance (bottleneck crossover).

## I5: Credit-Safe Fabric
**Invariant:** The mesh router must never drop flits and must never send flits to a downstream port lacking buffer space.
**Hardware Enforcement:**
The `srmesh_router` uses strict credit-based flow control. Assertions verify that `credits >= 0` and that a flit is never granted when credits are zero. The router also guarantees fairness via a Starvation Prevention counter (16-cycle force grant).
