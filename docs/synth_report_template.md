# ============================================================================
// SRMIC Synthesis Report Template
# ============================================================================

This document outlines the expected resource utilization and synthesis flow 
for the SRMIC-X1 prototype.

### 1. Synthesis Flow (Yosys)
```bash
make synth
```
The flow performs a generic techmap to standard cells to estimate area and 
gate count.

### 2. Key Metrics to Record
| Metric | Expected Range | Description |
|---|---|---|
| Total Cells | 5,000 - 8,000 | Total combinational + sequential logic |
| Flip-flops (DFF) | 1,200 - 1,800 | Sequential state elements |
| Memory (Inferred) | 4 regions x 64 entries | Tag RAM and LRU storage |

### 3. Critical Warnings
Review the synthesis log for the following:
* **Latch Inference:** Always-comb blocks must be complete. No latches are 
  permitted in the SRMIC microarchitecture.
* **Unconnected Ports:** Debug observability ports (`dbg_*`) may be optimized 
  away if not tied to a top-level sink.
* **Multi-driven Nets:** Ensure no bus contention in the `srmesh` logic.

### 4. Area Proxies
The synthesis netlist (`build/srmic_synth.v`) should be reviewed for gate 
density in the `hrm_region` tag matching logic, which is the most 
area-sensitive component of the residency controller.
