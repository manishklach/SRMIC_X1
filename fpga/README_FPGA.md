# ============================================================================
# FPGA Prototyping
# ============================================================================

This directory contains the necessary scaffolding to map the SRMIC RTL onto 
a physical FPGA target (baseline Xilinx Artix-7).

### Purpose
While SRMIC-X1 is an ASIC architecture targeting 1GHz+ implementation, 
synthesizing the logic to an FPGA provides:
1.  **Toolchain Sanity:** Proves the RTL is fully compatible with Vivado.
2.  **Resource Estimation:** Provides LUT/FF counts that serve as an alternative 
    proxy for logic density compared to Yosys generic mapping.

### Flow
```bash
make fpga-synth
```
This triggers the `synth_fpga.tcl` script in batch mode to elaborate the 
design and produce a utilization report. No full bitstream is strictly 
required at this stage.
