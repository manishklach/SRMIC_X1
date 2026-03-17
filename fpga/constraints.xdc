# constraints.xdc
# Basic constraints for Artix-7 baseline synthesis

# 100 MHz System Clock
create_clock -period 10.000 -name sys_clk -waveform {0.000 5.000} [get_ports sys_clk]

# Basic I/O (Dummy pins for out-of-context synthesis)
set_property PACKAGE_PIN W5 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

set_property PACKAGE_PIN U18 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

set_property PACKAGE_PIN U16 [get_ports led_hit]
set_property IOSTANDARD LVCMOS33 [get_ports led_hit]

set_property PACKAGE_PIN E19 [get_ports led_miss]
set_property IOSTANDARD LVCMOS33 [get_ports led_miss]

set_property PACKAGE_PIN U19 [get_ports led_throttle]
set_property IOSTANDARD LVCMOS33 [get_ports led_throttle]
