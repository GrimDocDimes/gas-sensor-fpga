## =============================================================================
## Gas Sensing System — Nexys 4 DDR Pin Constraints
## Board:  Nexys 4 DDR / Nexys A7-100T (XC7A100T-CSG324)
## Target: Vivado 2023.x
##
## References:
##   Nexys 4 DDR Reference Manual (Digilent, Rev. D)
##   Artix-7 FPGA Data Sheet (DS181)
## =============================================================================

## =============================================================================
## System Clock — 100 MHz on-board oscillator
## =============================================================================
set_property -dict {PACKAGE_PIN E3  IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -name sys_clk -period 10.000 [get_ports CLK100MHZ]

## =============================================================================
## Reset — CPU_RESETN (active-low push button, upper-left)
## =============================================================================
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

## =============================================================================
## JXADC Analog Input — VAUXP6 / VAUXN6
##
## IMPORTANT: Verify these pin names against the Nexys 4 DDR Reference Manual,
## Table 15 ("XADC Header"). The default here uses JA connector pair 1/7.
##
## JXADC Header (J4) mapping to XADC auxiliary channels (Nexys 4 DDR Rev D):
##   Pin 1  (JA1)  → VAUXP6  / AD6P → F5
##   Pin 7  (JA7)  → VAUXN6  / AD6N → D5
##   Pin 2  (JA2)  → VAUXP14 / AD14P
##   Pin 8  (JA8)  → VAUXN14 / AD14N
##   ... etc.
##
## Constraint uses DIFF_SSTL135 standard (internal to XADC block — use IOB=FALSE)
## =============================================================================
set_property -dict {PACKAGE_PIN F5  IOSTANDARD LVCMOS33} [get_ports VAUXP6]
set_property -dict {PACKAGE_PIN D5  IOSTANDARD LVCMOS33} [get_ports VAUXN6]

## =============================================================================
## UART — USB-UART bridge TX (FT2232H)
## =============================================================================
set_property -dict {PACKAGE_PIN D4  IOSTANDARD LVCMOS33} [get_ports UART_RXD_OUT]

## =============================================================================
## 7-Segment Display — 8 shared-anode digits, active-low
## =============================================================================
set_property -dict {PACKAGE_PIN J17 IOSTANDARD LVCMOS33} [get_ports {AN[0]}]
set_property -dict {PACKAGE_PIN J18 IOSTANDARD LVCMOS33} [get_ports {AN[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {AN[2]}]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports {AN[3]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {AN[4]}]
set_property -dict {PACKAGE_PIN T14 IOSTANDARD LVCMOS33} [get_ports {AN[5]}]
set_property -dict {PACKAGE_PIN K2  IOSTANDARD LVCMOS33} [get_ports {AN[6]}]
set_property -dict {PACKAGE_PIN U13 IOSTANDARD LVCMOS33} [get_ports {AN[7]}]

## Segments — active-low cathodes
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports CA]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports CB]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports CC]
set_property -dict {PACKAGE_PIN K13 IOSTANDARD LVCMOS33} [get_ports CD]
set_property -dict {PACKAGE_PIN P15 IOSTANDARD LVCMOS33} [get_ports CE]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports CF]
set_property -dict {PACKAGE_PIN L18 IOSTANDARD LVCMOS33} [get_ports CG]
set_property -dict {PACKAGE_PIN H15 IOSTANDARD LVCMOS33} [get_ports DP]

## =============================================================================
## LEDs — active-high
## =============================================================================
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]

## RGB LEDs
set_property -dict {PACKAGE_PIN R12 IOSTANDARD LVCMOS33} [get_ports LED16_R]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports LED16_G]
set_property -dict {PACKAGE_PIN N13 IOSTANDARD LVCMOS33} [get_ports LED16_B]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports LED17_R]
set_property -dict {PACKAGE_PIN R11 IOSTANDARD LVCMOS33} [get_ports LED17_G]
set_property -dict {PACKAGE_PIN R10 IOSTANDARD LVCMOS33} [get_ports LED17_B]

## =============================================================================
## Buttons (active-high)
## =============================================================================
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports BTNC]

## =============================================================================
## Switches
## =============================================================================
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]

## =============================================================================
## Timing Constraints
## =============================================================================
## False paths on asynchronous button and switch inputs
set_false_path -from [get_ports BTNC]
set_false_path -from [get_ports {SW[0]}]
set_false_path -from [get_ports CPU_RESETN]

## =============================================================================
## Configuration
## =============================================================================
set_property CFGBVS VCCO         [current_design]
set_property CONFIG_VOLTAGE 3.3  [current_design]
