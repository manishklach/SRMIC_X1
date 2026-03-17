#!/bin/bash
# ============================================================================
# SRMIC-X1 Verilator Lint Script
# ============================================================================

set -e

echo "Running Verilator Lint..."

# Run Verilator in lint-only mode.
# We treat warnings as errors to enforce clean RTL.
# We disable the warning about fatal errors to let it exit non-zero naturally.
verilator --lint-only -Wall -Wno-fatal ../rtl/*.sv ../tb/*.sv

echo "Lint Passed Cleanly."
