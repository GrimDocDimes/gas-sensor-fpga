## =============================================================================
## Gas Sensing System — Vivado Project Creation Script
## Board:  Nexys 4 DDR (xc7a100tcsg324-1)
## Target: Vivado 2023.x
##
## Usage (in Vivado Tcl Console):
##   source fpga/scripts/create_project.tcl
##
## Or from the command line:
##   vivado -mode batch -source fpga/scripts/create_project.tcl
## =============================================================================

## Set paths relative to this script's location
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize "$script_dir/../.."]

## Project settings
set project_name "gas_sensing"
set project_dir  "$project_root/fpga/vivado_project"
set part         "xc7a100tcsg324-1"
set board        "digilentinc.com:nexys4_ddr:part0:1.1"

puts "Creating Vivado project: $project_name"
puts "  Root:  $project_root"
puts "  Dir:   $project_dir"
puts "  Part:  $part"

## =============================================================================
## Create Project
## =============================================================================
create_project $project_name $project_dir -part $part -force

## Board definition (downloads board files if not present)
catch { set_property BOARD_PART $board [current_project] }

## =============================================================================
## Add RTL Sources
## =============================================================================
set src_files [list \
    "$project_root/fpga/src/top.v"               \
    "$project_root/fpga/src/xadc_gas_wrapper.v"  \
    "$project_root/fpga/src/baseline_delta.v"    \
    "$project_root/fpga/src/debounce.v"          \
    "$project_root/fpga/src/seg7_display.v"      \
    "$project_root/fpga/src/seg7_decoder.v"      \
    "$project_root/fpga/src/uart_tx.v"           \
    "$project_root/fpga/src/uart_framer.v"       \
    "$project_root/fpga/src/warmup_timer.v"      \
]

add_files -norecurse $src_files
set_property top top [current_fileset]

## =============================================================================
## Add Simulation Sources
## =============================================================================
set sim_files [list \
    "$project_root/fpga/sim/tb_xadc_gas_wrapper.v" \
    "$project_root/fpga/sim/tb_baseline_delta.v"   \
    "$project_root/fpga/sim/tb_uart_tx.v"          \
]

add_files -fileset sim_1 -norecurse $sim_files

## =============================================================================
## Add Constraints
## =============================================================================
add_files -fileset constrs_1 -norecurse \
    "$project_root/fpga/constraints/nexys4ddr_gas.xdc"

## =============================================================================
## Synthesis / Implementation Settings
## =============================================================================
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY  rebuilt [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.DIRECTIVE          Default  [get_runs synth_1]

set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE            Default  [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE          Default  [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE          Default  [get_runs impl_1]

## Generate bitstream after implementation
set_property STEPS.WRITE_BITSTREAM.ARGS.BIN_FILE        true     [get_runs impl_1]

## =============================================================================
## Launch Synthesis (optional — comment out if you want to configure IP first)
## =============================================================================
# launch_runs synth_1 -jobs 4
# wait_on_run synth_1

## =============================================================================
## NOTE: If using Vivado Divider IP (USE_DIVIDER_IP=1 in baseline_delta.v),
## add it here before running synthesis:
##
##   create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 \
##             -module_name div_gen_0
##   set_property -dict [list \
##       CONFIG.algorithm_type     {NonRestoring}  \
##       CONFIG.dividend_and_quotient_width {20}   \
##       CONFIG.divisor_width      {12}            \
##       CONFIG.latency_configuration {Manual}     \
##       CONFIG.latency            {17}            \
##       CONFIG.operand_sign       {Signed}        \
##   ] [get_ips div_gen_0]
##   generate_target all [get_ips div_gen_0]
##
## =============================================================================

puts "Project created successfully."
puts "Next steps:"
puts "  1. Review and correct VAUXP6/VAUXN6 pin assignments in the XDC file."
puts "  2. Run synthesis: launch_runs synth_1 -jobs 4"
puts "  3. Run implementation: launch_runs impl_1 -jobs 4"
puts "  4. Generate bitstream: launch_runs impl_1 -to_step write_bitstream -jobs 4"
