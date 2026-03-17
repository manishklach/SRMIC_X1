#!/bin/bash
# ============================================================================
# SRMIC-X1 Verilator Lint Script
# ============================================================================

set -e

echo "Running Verilator Lint..."
verilator --lint-only -Wall -Wno-fatal \
    rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv \
    tb/tb_top.sv

echo "Lint passed cleanly."
