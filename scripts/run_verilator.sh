#!/bin/bash
# Verilator Run Script for SRMIC-X1 Bring-up

set -e

# Configuration
TOP_MODULE="srmic_top"
RTL_DIR="../rtl"
TB_DIR="../tb"
OBJ_DIR="obj_dir"

echo "[1/3] Compiling RTL and Testbench..."
verilator --cc ${RTL_DIR}/ric.sv ${RTL_DIR}/hrm_region.sv ${RTL_DIR}/srmesh_router.sv ${RTL_DIR}/srmic_top.sv \
          --exe ${TB_DIR}/tb_top.sv --top-module ${TOP_MODULE} \
          --trace --assert -Wno-fatal -Mdir ${OBJ_DIR}

echo "[2/3] Building Executable..."
make -C ${OBJ_DIR} -j -f V${TOP_MODULE}.mk V${TOP_MODULE}

echo "[3/3] Running Simulation..."
./${OBJ_DIR}/V${TOP_MODULE}

echo "Simulation complete. VCD generated: srmic_bringup.vcd"
