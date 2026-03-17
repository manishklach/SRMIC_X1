# ============================================================================
# SRMIC-X1 RTL Bring-up Documentation
# ============================================================================

This document provides technical instructions for simulating and reviewing 
the SRMIC-X1 RTL prototype.

### 1. Repository Structure
*   `rtl/`: Synthesizable SystemVerilog source files.
*   `tb/`: System-level testbench and scoreboard.
*   `scripts/`: Build, lint, and synthesis automation scripts.
*   `docs/`: Hardware specifications and architectural invariants.
*   `build/`: (Generated) Simulation artifacts and synthesis logs.

### 2. Simulation Quickstart
The project uses a standard Makefile flow.

```bash
# Verilator (Recommended for speed and SVA)
make sim

# Icarus Verilog (Fallback)
make sim-iverilog
```

### 3. Waveform Analysis
After simulation, open `build/srmic_trace.vcd` in GTKWave or Surfer.

**Critical Signals to Monitor:**
*   `dut.dbg_ric_state`: FSM arbitration flow.
*   `dut.i_ric.occupancy[3:0]`: Real-time region fill levels.
*   `dut.gen_regions[0].i_hrm.bank_conflict_count`: Monitor memory contention.
*   `dut.i_router.starvation_cnt`: Fabric fairness watchdog status.

### 4. Metrics & Performance
The simulation generates `build/sim_results.log` with the following:
*   **Cycles:** Total simulation duration.
*   **Hit Rate:** Percentage of tokens served from hot SRAM.
*   **Avg Latency:** Weighted access cost (target < 5.0 cycles).
*   **Status:** PASS/FAIL based on scoreboard validation.

### 5. Prototype Limitations
*   **Top-level Interconnect:** The current `srmic_top` instantiates a single 
    router instance for verification sanity; the full 32-node mesh is 
    described in the architecture whitepaper.
*   **SRAM Models:** Memory is inferred as registers. Physical macro mapping 
    is required for GDSII generation.
