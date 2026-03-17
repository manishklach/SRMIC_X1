#!/bin/bash
# ============================================================================
# SRMIC-X1 Verilator Simulation Script
# ============================================================================

set -e

mkdir -p build
echo "Compiling RTL..."
verilator --binary --timing --trace --assert -Wno-fatal -Mdir build/obj_dir \
    rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv \
    tb/tb_top.sv --top-module tb_top

echo "Running Simulation..."
./build/obj_dir/Vtb_top +seed=1234
