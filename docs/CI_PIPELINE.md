# ============================================================================
# Continuous Integration (CI) Pipeline
# ============================================================================

The SRMIC-X1 repository uses GitHub Actions to enforce RTL quality on every 
push and pull request.

### CI Stages
1.  **Dependencies:** Installs OSS EDA tools (`verilator`, `iverilog`, 
    `yosys`, `symbiyosys`, `boolector`).
2.  **Lint (`make lint`):** Runs Verilator in strict lint-only mode. Any 
    warnings (e.g., width mismatches, unconnected ports) cause failure.
3.  **Simulation (`make sim`):** Compiles and runs the `tb_top` testbench 
    for 20,000 cycles. It fails if the scoreboard flags any architectural 
    mismatches or if assertions trigger.
4.  **Synthesis (`make synth`):** Runs Yosys hierarchy checks and generic 
    cell mapping. Fails on latches or unresolvable combinatorial loops.
5.  **Formal Verification (`make formal`):** Executes SBY proofs on the 
    submodules to guarantee bounded model safety.

A green CI badge indicates the RTL is functionally sound, syntactically clean, 
and logically synthesizable.
