# SRMIC-X1 Synthesis Sanity Notes

## 1. Top Module: `srmic_top`
The top-level integrates the controller, residency memory, and fabric router.

## 2. Expected Warnings (Yosys)
* **Unconnected signals:** Some observability ports in the top level may be optimized away if not tied to pins.
* **Latch detection:** Always-comb blocks are rigorously checked; no latches should be present.
* **Unused bits:** In `srmesh_router`, some bits of the `FLIT_WIDTH` (64 bits) are for future expansion and may trigger "unused bit" warnings.

## 3. Synthesis Constructs
The design uses only **fully synthesizable SystemVerilog constructs**:
* `always_ff` for sequential logic.
* `always_comb` for combinational logic.
* No `initial` blocks in the RTL (only in the testbench).
* No `#delay` or behavioral-only modeling.

## 4. Prototype Limitations
* **SRAM Macros:** The `hrm_region` tag array and valid bits are currently inferred as registers. In production, these should be mapped to high-density SRAM macros via a technology-specific wrapper.
* **Virtual Channels:** Buffers are implemented as flops. For larger VCs, FIFO macros or dual-port SRAMs would be required.
* **Mesh Scalability:** The `srmic_top` currently provides a single-router integration as a sanity check. Scale to 32+ regions will require a hierarchical synthesis approach.
