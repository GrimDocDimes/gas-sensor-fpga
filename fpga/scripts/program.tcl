## =============================================================================
## Gas Sensing System — One-Shot Bitstream Program Script
## Board:  Nexys 4 DDR (connected via USB/JTAG)
##
## Usage (in Vivado Tcl Console after synthesis + implementation):
##   source fpga/scripts/program.tcl
## =============================================================================

set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize "$script_dir/../.."]
set bitfile "$project_root/fpga/vivado_project/gas_sensing.runs/impl_1/top.bit"

puts "Programming Nexys 4 DDR with: $bitfile"

if {![file exists $bitfile]} {
    error "Bitstream not found: $bitfile\nRun synthesis + implementation first."
}

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target

set device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE $bitfile $device
program_hw_devices $device
refresh_hw_device $device

puts "Programming done."
close_hw_target
disconnect_hw_server
close_hw_manager
