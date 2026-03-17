#!/bin/bash
# ============================================================================
# SRMIC-X1 Verilator Simulation Script
# ============================================================================

set -e

mkdir -p build
echo "Compiling RTL..."
verilator --cc --trace --assert -Wall -Wno-fatal -Mdir build/obj_dir \
    rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv \
    --exe tb/tb_top.sv --top-module srmic_top

echo "Building Simulator..."
make -C build/obj_dir -j -f Vsrmic_top.mk Vsrmic_top

echo "Running Simulation..."
./build/obj_dir/Vsrmic_top +seed=1234
