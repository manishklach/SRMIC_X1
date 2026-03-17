# synth_fpga.tcl
# Vivado Synthesis script for SRMIC-X1 logic validation

# Read source files
read_verilog -sv [glob ../rtl/*.sv]
read_verilog -sv srmic_fpga_top.sv

# Read constraints
read_xdc constraints.xdc

# Synthesize design
synth_design -top srmic_fpga_top -part xc7a35tcpg236-1

# Generate reports
report_utilization -file ../build/fpga_utilization.txt
report_timing_summary -file ../build/fpga_timing.txt

# Exit
exit
