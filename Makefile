# ============================================================================
# SRMIC-X1 Bring-up Makefile
# ============================================================================

.PHONY: all sim sim-iverilog synth lint clean

# Default target
all: lint sim

# Build directories
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj_dir

# Verilator configuration
VERILATOR_FLAGS = --cc --trace --assert -Wall -Wno-fatal -Mdir $(OBJ_DIR)

# RTL and TB sources
RTL_SRC = rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv
TB_SRC = tb/tb_top.sv
TOP_MODULE = srmic_top

# Run simulation with Verilator
sim: $(BUILD_DIR)
	@echo "--- [VERILATOR] Compiling ---"
	verilator $(VERILATOR_FLAGS) $(RTL_SRC) --exe ../$(TB_SRC) --top-module $(TOP_MODULE)
	@echo "--- [VERILATOR] Building executable ---"
	make -C $(OBJ_DIR) -j -f V$(TOP_MODULE).mk V$(TOP_MODULE)
	@echo "--- [VERILATOR] Running simulation ---"
	cd $(BUILD_DIR) && ./obj_dir/V$(TOP_MODULE) +seed=1234

# Run simulation with Icarus Verilog
sim-iverilog: $(BUILD_DIR)
	@echo "--- [IVERILOG] Compiling ---"
	iverilog -g2012 -o $(BUILD_DIR)/srmic_sim.vvp $(RTL_SRC) $(TB_SRC)
	@echo "--- [IVERILOG] Running simulation ---"
	cd $(BUILD_DIR) && vvp srmic_sim.vvp +seed=1234

# Run Yosys Synthesis
synth: $(BUILD_DIR)
	@echo "--- [YOSYS] Running synthesis sanity check ---"
	cd $(BUILD_DIR) && yosys ../scripts/run_yosys.ys

# Run Lint script
lint:
	@echo "--- [LINT] Running Verilator lint ---"
	./scripts/lint.sh

# Ensure build directory exists
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# Clean build artifacts
clean:
	@echo "--- Cleaning build directory ---"
	rm -rf $(BUILD_DIR)/*
