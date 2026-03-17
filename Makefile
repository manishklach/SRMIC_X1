# ============================================================================
# Makefile for SRMIC-X1 RTL Bring-up
# ============================================================================

# --- Parameters ---
TOP_MODULE = srmic_top
RTL_SRC    = rtl/ric.sv rtl/hrm_region.sv rtl/srmesh_router.sv rtl/srmic_top.sv
TB_SRC     = tb/tb_top.sv
BUILD_DIR  = build
OBJ_DIR    = $(BUILD_DIR)/obj_dir
SEED       = 1234

# --- Tools ---
VERILATOR  = verilator
IVERILOG   = iverilog
VVP        = vvp
YOSYS      = yosys

.PHONY: all sim sim-iverilog lint synth clean

all: lint sim

# --- Verilator Simulation ---
sim: $(BUILD_DIR)
	@echo "--- [VERILATOR] Compiling and Building ---"
	$(VERILATOR) --cc --trace --assert -Wall -Wno-fatal -Mdir $(OBJ_DIR) $(RTL_SRC) --exe ../$(TB_SRC) --top-module $(TOP_MODULE)
	make -C $(OBJ_DIR) -j -f V$(TOP_MODULE).mk V$(TOP_MODULE)
	@echo "--- [VERILATOR] Running Simulation ---"
	cd $(BUILD_DIR) && ./obj_dir/V$(TOP_MODULE) +seed=$(SEED)

# --- Icarus Verilog Simulation ---
sim-iverilog: $(BUILD_DIR)
	@echo "--- [IVERILOG] Compiling ---"
	$(IVERILOG) -g2012 -o $(BUILD_DIR)/srmic_sim.vvp $(RTL_SRC) $(TB_SRC)
	@echo "--- [IVERILOG] Running Simulation ---"
	cd $(BUILD_DIR) && $(VVP) srmic_sim.vvp +seed=$(SEED)

# --- Linting ---
lint:
	@echo "--- [LINT] Running Verilator Lint ---"
	./scripts/lint.sh

# --- Synthesis ---
synth: $(BUILD_DIR)
	@echo "--- [YOSYS] Running Synthesis Sanity Check ---"
	$(YOSYS) scripts/run_yosys.ys

# --- Setup & Cleanup ---
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	@echo "--- Cleaning Build Artifacts ---"
	rm -rf $(BUILD_DIR)
