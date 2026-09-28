# =============================================================================
# Constraint File : pynqz2_gas_sensor.xdc
# Target          : PYNQ-Z2 (xc7z020clg400-1)
# Project         : FPGA-Based Multi-Channel Gas Sensor Acquisition System
#
# WARNING:
#   The XADC VAUX pin assignments (Section 1) are taken from community XDC
#   sources and the Digilent PYNQ-Z2 Master XDC.  Verify each assignment
#   against the official PYNQ-Z2 Rev C schematic before programming hardware.
#   An incorrect VAUX assignment will cause the XADC to read from the wrong
#   sensor channel — no damage, but wrong data.
#
# Notes:
#   - XADC VAUX pins are FIXED FUNCTION (cannot be reassigned via XDC)
#   - They are declared here for documentation; Vivado infers them from the
#     XADC Wizard IP configuration
#   - The FCLK_CLK0 and aresetn are driven by the PS and managed in the
#     block design — not constrained here
# =============================================================================

# ── Section 1: XADC Auxiliary Analog Input Pin Declarations ─────────────────
# These inform Vivado which physical pins carry the XADC differential pairs.
# In the Vivado block design, the XADC Wizard IP configuration must match.
#
# Arduino A0 → VAUX1
set_property PACKAGE_PIN N15 [get_ports {vauxp[0]}]  ;# VAUX1P (A0)
set_property PACKAGE_PIN N16 [get_ports {vauxn[0]}]  ;# VAUX1N (A0)
# Arduino A1 → VAUX9
set_property PACKAGE_PIN K15 [get_ports {vauxp[1]}]  ;# VAUX9P (A1)
set_property PACKAGE_PIN L15 [get_ports {vauxn[1]}]  ;# VAUX9N (A1)
# Arduino A2 → VAUX6
set_property PACKAGE_PIN R17 [get_ports {vauxp[2]}]  ;# VAUX6P (A2) — VERIFY
set_property PACKAGE_PIN T17 [get_ports {vauxn[2]}]  ;# VAUX6N (A2) — VERIFY
# Arduino A3 → VAUX15
set_property PACKAGE_PIN H15 [get_ports {vauxp[3]}]  ;# VAUX15P (A3) — VERIFY
set_property PACKAGE_PIN G15 [get_ports {vauxn[3]}]  ;# VAUX15N (A3) — VERIFY
# Arduino A4 → VAUX5
set_property PACKAGE_PIN J14 [get_ports {vauxp[4]}]  ;# VAUX5P (A4) — VERIFY
set_property PACKAGE_PIN J15 [get_ports {vauxn[4]}]  ;# VAUX5N (A4) — VERIFY
# Arduino A5 → VAUX13
set_property PACKAGE_PIN G14 [get_ports {vauxp[5]}]  ;# VAUX13P (A5) — VERIFY
set_property PACKAGE_PIN F14 [get_ports {vauxn[5]}]  ;# VAUX13N (A5) — VERIFY

# XADC pins use analog I/O standard — no IOSTANDARD constraint needed
# (Vivado applies ANALOG standard automatically for XADC pins)

# ── Section 2: Alarm Output — On-Board LED LD0 ───────────────────────────────
# LD0 on PYNQ-Z2 is connected to pin M14
set_property PACKAGE_PIN M14 [get_ports {alarm_out}]
set_property IOSTANDARD LVCMOS33 [get_ports {alarm_out}]

# ── Section 3: Per-Channel Fault LEDs (LD1-LD3, optional) ────────────────────
# PYNQ-Z2 has 4 user LEDs: LD0(M14), LD1(M15), LD2(G14), LD3(D18)
# Use LD1-LD3 for first 3 channel faults; remainder readable via AXI
set_property PACKAGE_PIN M15 [get_ports {fault_out[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {fault_out[0]}]
set_property PACKAGE_PIN G14 [get_ports {fault_out[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {fault_out[1]}]
set_property PACKAGE_PIN D18 [get_ports {fault_out[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {fault_out[2]}]

# ── Section 4: Timing Constraints ────────────────────────────────────────────

# Primary clock (50 MHz from PS FCLK_CLK0 — also defined in block design)
# If clk is a top-level port (not in block design), define here:
# create_clock -period 20.000 -name clk_pl [get_ports clk]
# If using block design FCLK_CLK0, this is auto-constrained — skip above.

# False path: alarm_out is a level signal driving an LED.
# LED driver need not meet setup/hold relative to any other clock domain.
set_false_path -to [get_ports {alarm_out}]
set_false_path -to [get_ports {fault_out[*]}]

# Multicycle path: The sequential divider in div_pipe and cross_channel_fault
# runs one restoring step per clock cycle.  No multicycle path is needed since
# the critical path is a single subtract+compare, not a multi-cycle operation.
# Document here: the pipelined FSM does NOT use a multicycle path constraint.

# ── Section 5: Configuration / Bitstream ─────────────────────────────────────
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

# ── Section 6: Synthesis Attributes (applied in RTL — documented here) ────────
# (These are set via (* *) attributes in the RTL source, not XDC)
# (* keep_hierarchy = "yes" *)  on gas_sensor_top — preserves hierarchy in reports
# (* use_dsp = "no" *)          on div_pipe — force LUT implementation (no DSP48
#                                needed at 50 MHz for this latency-tolerant path)
