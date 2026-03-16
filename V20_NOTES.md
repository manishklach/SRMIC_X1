# V20_NOTES

## Architectural Correction

The per-region working set is now treated as FIXED by model architecture,
not as a function of HRM occupancy. This reflects the physical reality
that each token decode step accesses a bounded working set per region —
determined by active weight distribution, not by how much is resident.

HRM hit ratio controls the FRACTION of that fixed working set served
from fast SRAM. Higher hit ratio reduces HBM traffic without increasing
HRM access time per region.

This is the correct model for a distributed banked SRAM architecture
where regions operate in parallel and access latency is bounded by
the per-region working set, not total aggregate occupancy.

Previous versions (v18, v19) incorrectly grew hrm_time with occupancy,
creating artificial non-monotonic speedup curves.
