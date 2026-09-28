# Multi-Channel Resistive Gas Sensor Acquisition FPGA System

## Overview

This repository contains FPGA implementations for resistive MOx gas sensor array acquisition systems, targeted primarily at the **PYNQ-Z2 (Zynq-7000 XC7Z020)** PL/PS architecture with support for legacy Artix-7 board scaffolds.

---

## Primary Project: PYNQ-Z2 6-Channel Multi-Resistive Sensor Acquisition System

A 6-channel resistive gas sensor array signal acquisition, baseline tracking, rate-of-change (dR/dt) detection, cross-channel fault verification, and alarm controller system.

### Architecture Overview
- **Device**: Xilinx Zynq-7000 (xc7z020clg400-1) on PYNQ-Z2
- **Input Channels**: 6 Single-Ended Analog Channels (A0–A5 / VAUX1, VAUX9, VAUX6, VAUX15, VAUX5, VAUX13)
- **Clock Domain**: 50 MHz PL Clock (`clk`)
- **System Interface**: AXI4-Lite Slave (`s_axi_aclk`, Base `0x43C0_0000`)
- **Alarm Output**: On-board LED `LD0` driven by registered Moore FSM with priority handling

```
   ┌────────────────┐
   │ 6× Gas Sensors │
   └───────┬────────┘
           │ (Analog 0..1.3391V)
           ▼
   ┌────────────────┐     DRP     ┌─────────────────┐
   │ XADC Wizard IP │ ──────────► │ xadc_sequencer  │
   └────────────────┘             └────────┬────────┘
                                           │ (12-bit ADC code)
                                           ▼
                                  ┌─────────────────┐
                                  │ resistance_calc │
                                  └────────┬────────┘
                                           │ (32-bit Resistance Ω)
                  ┌────────────────────────┼────────────────────────┐
                  ▼                        ▼                        ▼
        ┌──────────────────┐     ┌──────────────────┐    ┌─────────────────────┐
        │ baseline_tracker │     │   roc_detector   │    │ cross_channel_fault │
        └──────────────────┘     └────────┬─────────┘    └──────────┬──────────┘
                                          │                         │
                                          ▼                         ▼
                                 ┌────────────────────────────────────┐
                                 │          alarm_controller          │
                                 └─────────────────┬──────────────────┘
                                                   │
                                                   ▼
                                         LED LD0 / AXI-Lite Regs
```

### RTL Modules (`rtl/`)
| Module | Description |
|---|---|
| [`gas_sensor_top.v`](file:///home/jhush/testurop/rtl/gas_sensor_top.v) | Top-level integration connecting XADC sequencer, processing chain, alarm controller, and AXI-Lite registers |
| [`div_pipe.v`](file:///home/jhush/testurop/rtl/div_pipe.v) | Fully sequential restoring pipelined/iterative divider (27-cycle exact division) |
| [`resistance_calc.v`](file:///home/jhush/testurop/rtl/resistance_calc.v) | Fixed-point voltage-to-resistance calculator with over-range / under-range flags |
| [`baseline_tracker.v`](file:///home/jhush/testurop/rtl/baseline_tracker.v) | Exponential moving average (EMA, $\alpha=1/2^N$) baseline tracker per channel |
| [`roc_detector.v`](file:///home/jhush/testurop/rtl/roc_detector.v) | Rate-of-change ($|R[n] - R[n-1]| > \text{ROC\_THRESH}$) alarm detector per channel |
| [`cross_channel_fault.v`](file:///home/jhush/testurop/rtl/cross_channel_fault.v) | Exact mean deviation detector distinguishing global gas exposures from single-sensor faults |
| [`alarm_controller.v`](file:///home/jhush/testurop/rtl/alarm_controller.v) | Glitch-free Moore FSM alarm aggregator with sticky latch & PS acknowledgement |
| [`axi_lite_regs.v`](file:///home/jhush/testurop/rtl/axi_lite_regs.v) | AXI4-Lite slave register file exposing live raw code, resistance, baseline, status & thresholds |
| [`xadc_sequencer.v`](file:///home/jhush/testurop/rtl/xadc_sequencer.v) | DRP read FSM for XADC Wizard IP sequence polling |

---

## Verification & Simulation (`sim/`)

All RTL modules are thoroughly verified using self-checking Icarus Verilog (`iverilog`) testbenches.

### Run All Testbenches
```bash
cd sim
bash run_sims.sh
```

### Verification Suite Results
- `tb_resistance_calc.v` — **16/16 PASS**
- `tb_alarm_controller.v` — **9/9 PASS**
- `tb_baseline_tracker.v` — **5/5 PASS**
- `tb_roc_detector.v` — **5/5 PASS**
- `tb_cross_channel_fault.v` — **3/3 PASS**
- `tb_axi_lite_regs.v` — **5/5 PASS**

---

## Repository Structure

```
├── constraints/
│   └── pynqz2_gas_sensor.xdc    # PYNQ-Z2 XDC constraints (A0-A5, LED LD0)
├── docs/
│   └── design_spec.md           # Full FPGA Engineering Design Specification
├── rtl/                         # Synthesizable Verilog-2001 RTL sources
├── sim/                         # Self-checking testbenches and bash run script
├── testpython/                  # Calibration notebook and Python test scripts
│   ├── read_a0.ipynb            # Jupyter calibration notebook (V_FS = 1.3391V)
│   └── read_a0.py               # Live Python acquisition script
└── fpga/ & pc/                  # Legacy Nexys-4 DDR single-channel scaffold
```

---

## Documentation & Calibration

- Complete design specification available at [`docs/design_spec.md`](file:///home/jhush/testurop/docs/design_spec.md).
- Electrode calibration details in [`testpython/read_a0.ipynb`](file:///home/jhush/testurop/testpython/read_a0.ipynb).
