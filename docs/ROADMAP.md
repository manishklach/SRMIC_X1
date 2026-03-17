# ============================================================================
# SRMIC-X1 Engineering Roadmap
# ============================================================================

The SRMIC repository tracks the journey from architectural concept to silicon 
realization.

### 1. Architectural Modeling (Complete)
*   First-order latency models (`decode_core.py`).
*   Identification of the Bottleneck Crossover and Working Set Bounds.

### 2. RTL Prototype (Complete)
*   Synthesizable logic for the Residency Intelligence Controller, HRM Regions, 
    and Mesh Fabric.
*   Self-checking scoreboard testbench and performance automation.

### 3. Verification & CI (Complete)
*   Linting, SVA, and formal property checking (SymbiYosys).
*   Automated GitHub Actions pipeline.

### 4. Physical Scaffolding (Current)
*   **FPGA Target:** Out-of-context synthesis wrapper for Artix-7 validation.
*   **Multi-Chiplet Simulation:** Initial framework for simulating off-chip 
    fabric extensions (`tb_multichiplet.sv`).

### 5. Tapeout Preparation (Future)
*   **SRAM Macro Integration:** Replace `reg` arrays in `hrm_region` with 
    foundry-specific dual-port SRAM macros (e.g., TSMC/GF libraries).
*   **Package Modeling:** Advanced multi-die structural synthesis and bump 
    mapping for 2.5D interposer layouts.
*   **Gate-Level Simulation (GLS):** Post-synthesis timing validation.
