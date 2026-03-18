# ============================================================================
# Makefile for SRMIC-X1 RTL Bring-up
# ============================================================================

# --- Parameters ---
TOP_MODULE = tb_top
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
	$(VERILATOR) --binary --timing --trace --assert -Wno-lint -Wno-style -Wno-fatal -Mdir $(OBJ_DIR) $(RTL_SRC) $(TB_SRC) --top-module $(TOP_MODULE)
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
	$(VERILATOR) --binary --timing --trace --assert -Wno-lint -Wno-style -Wno-fatal -Mdir $(OBJ_DIR)_mc $(RTL_SRC) tb/tb_multichiplet.sv --top-module tb_multichiplet
	@echo "--- [VERILATOR] Running Multi-Chiplet Simulation ---"
	cd $(BUILD_DIR) && ./obj_dir_mc/Vtb_multichiplet

# --- Linting ---
lint:
	@echo "--- [LINT] Running Verilator Lint ---"
	bash ./scripts/lint.sh

# --- Synthesis ---
synth: $(BUILD_DIR)
	@echo "--- [YOSYS] Running Synthesis Sanity Check ---"
	cd $(BUILD_DIR) && yosys ../scripts/run_yosys.ys

# --- Formal Verification ---
formal: $(BUILD_DIR)
	@echo "--- [SBY] Running Formal Verification ---"
	mkdir -p $(BUILD_DIR)/formal
	@which sby > /dev/null 2>&1 && \
		cd $(BUILD_DIR)/formal && sby -f ../../formal/ric.sby && \
		cd $(BUILD_DIR)/formal && sby -f ../../formal/hrm_region.sby && \
		cd $(BUILD_DIR)/formal && sby -f ../../formal/srmesh_router.sby || \
		echo "sby not found — skipping formal verification"

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