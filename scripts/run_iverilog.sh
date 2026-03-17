#!/bin/bash
# ============================================================================
# SRMIC-X1 Icarus Verilog Simulation Script
# ============================================================================

set -e

mkdir -p build
echo "Compiling with Icarus..."
iverilog -g2012 -o build/srmic_sim.vvp \
    rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv \
    tb/tb_top.sv

echo "Running simulation..."
vvp build/srmic_sim.vvp +seed=1234
