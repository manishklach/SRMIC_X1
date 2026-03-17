# ============================================================================
# SRMIC Architectural Invariants
# ============================================================================

The SRMIC-X1 hardware enforces the following invariants via SystemVerilog 
Assertions (SVA) and structural design.

### I1: Region Capacity Bounded
A region's entry count (`occupancy`) must never exceed its physical 
depth (`REGION_DEPTH`). The RIC maintains an explicit counter per 
region and triggers demotions before promoting new pages to a full region.

### I2: No Double Residency
A single `page_id` cannot reside in the same (or multiple) HRM regions 
simultaneously. This is enforced by the **Pin Register File (CAM)** 
in the RIC, which squashes duplicate promotion requests.

### I3: Deterministic Victim Selection
Victim selection for both region-level demotions and entry-level 
replacement is deterministic. HRM regions use a true 3-bit **LRU (Least 
Recently Used)** counter array to select the oldest entry for eviction.

### I4: Bounded Working Set
The system uses a **Token Bucket** throttle to rate-limit promotions. 
This ensures that fabric bandwidth and residency capacity are not 
overwhelmed by rapid weight thrashing.

### I5: Credit-Safe Fabric
The `srmesh_router` implements a **credit-based flow control** 
mechanism. Flits are only granted egress when the downstream neighbor 
has available buffer space. This prevents data loss during fabric 
congestion.

### I6: Bank Conflict Observability
Memory bank contention is explicitly modeled and tracked. Concurrent 
accesses to the same bank map to stalls, ensuring that aggregate 
performance reflects the physical limitations of distributed SRAM tiles.
