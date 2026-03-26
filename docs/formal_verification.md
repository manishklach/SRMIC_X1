# ============================================================================
# Formal Verification Methodology
# ============================================================================

This repository uses **SymbiYosys (SBY)** for formal verification of critical 
hardware invariants.

### 1. Verification Scope
The formal test suite proves structural and behavioral invariants on the core modules:
*   `ric.sby`: Proves FIFO bounds, region occupancy bounds (<= `REGION_DEPTH`), 
    and promotion/demotion atomicity.
*   `hrm_region.sby`: Proves valid tag assumptions, mutual exclusion of hit/miss 
    responses, and deterministic victim bounds.
*   `srmesh_router.sby`: Proves credit underflow prevention and output routing 
    integrity.

### 2. Bounded Model Checking (BMC)
The formal engine uses BMC with a depth of up to 32 cycles. This depth is 
sufficient to exhaustively explore the state space of the pipelines (which 
are typically < 10 cycles deep) and the router starvation mechanism (16 cycles).

### 3. Execution
To run the formal proofs:
```bash
make formal
```
Results are aggregated in the `build/formal/` directory.

### 4. Known Limitations
*   The mesh router formal check uses a reduced depth (16) to constrain 
    solver time on the complex combinational arbitration tree.
*   Liveness properties (`eventually`) are partially modeled via starvation 
    counters rather than unbounded temporal proofs.
