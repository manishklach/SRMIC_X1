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
SBY        = sby
VIVADO     = vivado

.PHONY: all sim sim-iverilog lint synth formal perf-sweep fpga-synth sim-multichiplet clean

all: lint sim formal synth

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

# --- Multi-Chiplet Simulation Scaffold ---
sim-multichiplet: $(BUILD_DIR)
	@echo "--- [VERILATOR] Compiling Multi-Chiplet TB ---"
	$(VERILATOR) --cc --trace --assert -Wall -Wno-fatal -Mdir $(OBJ_DIR)_mc $(RTL_SRC) --exe ../tb/tb_multichiplet.sv --top-module tb_multichiplet
	make -C $(OBJ_DIR)_mc -j -f Vtb_multichiplet.mk Vtb_multichiplet
	@echo "--- [VERILATOR] Running Multi-Chiplet Simulation ---"
	cd $(BUILD_DIR) && ./obj_dir_mc/Vtb_multichiplet

# --- Linting ---
lint:
	@echo "--- [LINT] Running Verilator Lint ---"
	./scripts/lint.sh

# --- Synthesis Sanity ---
synth: $(BUILD_DIR)
	@echo "--- [YOSYS] Running Synthesis Sanity Check ---"
	$(YOSYS) scripts/run_yosys.ys

# --- Formal Verification ---
formal: $(BUILD_DIR)
	@echo "--- [SBY] Running Formal Verification ---"
	mkdir -p $(BUILD_DIR)/formal
	cd $(BUILD_DIR)/formal && $(SBY) -f ../../formal/ric.sby
	cd $(BUILD_DIR)/formal && $(SBY) -f ../../formal/hrm_region.sby
	cd $(BUILD_DIR)/formal && $(SBY) -f ../../formal/srmesh_router.sby
	@echo "Formal Verification: PASS"

# --- Performance Sweep ---
perf-sweep: $(BUILD_DIR)
	@echo "--- [SWEEP] Running Performance Parameter Sweep ---"
	python3 scripts/perf_sweep.py

# --- FPGA Synthesis Scaffold ---
fpga-synth: $(BUILD_DIR)
	@echo "--- [FPGA] Running Out-of-Context Synthesis ---"
	cd $(BUILD_DIR) && $(VIVADO) -mode batch -source ../scripts/synth_fpga.tcl

# --- Setup & Cleanup ---
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	@echo "--- Cleaning Build Artifacts ---"
	rm -rf $(BUILD_DIR)/*
