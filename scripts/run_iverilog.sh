#!/bin/bash
# Icarus Verilog Run Script for SRMIC-X1 Bring-up

set -e

TOP_MODULE="srmic_top"
RTL_DIR="../rtl"
TB_DIR="../tb"
OUT_FILE="srmic_sim.vvp"

echo "[1/2] Compiling RTL and Testbench..."
iverilog -g2012 -o ${OUT_FILE} \
    ${RTL_DIR}/ric.sv \
    ${RTL_DIR}/hrm_region.sv \
    ${RTL_DIR}/srmesh_router.sv \
    ${RTL_DIR}/srmic_top.sv \
    ${TB_DIR}/tb_top.sv

echo "[2/2] Running Simulation..."
vvp ${OUT_FILE}

echo "Simulation complete. VCD generated: srmic_bringup.vcd"
