# ================================================================
# ftj_controller_constraints.sdc
# SDC Timing Constraints — FTJ SSD Controller IP Block
# Target clock: 100 MHz (10 ns period)
# ================================================================

# Primary clock definition
create_clock -name clk -period 10.0 [get_ports clk]

# Input/output delays (20% of clock period)
set_input_delay  2.0 -clock clk [all_inputs]
set_output_delay 2.0 -clock clk [all_outputs]

# Max combinational delay (80% of period after I/O delays)
set_max_delay 6.0 -from [all_registers -clock_pins] -to [all_registers -data_pins]

# False paths on async reset
set_false_path -from [get_ports rst_n]

# Multicycle paths (NAND wait counters are pipelined across many cycles)
set_multicycle_path 2 -setup -from [get_cells -hierarchical *nand_wait_cnt*]
set_multicycle_path 1 -hold  -from [get_cells -hierarchical *nand_wait_cnt*]
