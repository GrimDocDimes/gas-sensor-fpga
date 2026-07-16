# Breath-Based Gas Sensing System
## Nexys 4 DDR / Artix-7 XC7A100T — XADC Resistive Gas Sensor

---

## Quick Overview

A real-time gas sensing system that reads a 2-pin MOx resistive analog gas sensor
through the Nexys 4 DDR's on-chip XADC, computes deviation from a clean-air baseline,
and displays the result on the 7-segment display while streaming data over UART.

```
[Gas Sensor + Voltage Dividers] --0-1V--> [XADC VAUXP/N] --12-bit--> [Baseline+Delta RTL]
                                                                               |
                                                    +--------------------------+---------------------------+
                                                    |                                                       |
                                            [7-Seg Display (8 digits)]                          [UART TX → USB-CDC]
                                                    |                                                       |
                                             (sensitivity % or ΔR)                                  (ASCII CSV frames)
                                                                                                            |
                                                                                                      [PC Logger]
```

---

## Hardware Requirements

| Item | Notes |
|------|-------|
| Nexys 4 DDR (or Nexys A7-100T) | Artix-7 XC7A100T |
| 2-pin resistive MOx gas sensor | e.g. MQ-2, MQ-7, TGS-series |
| 10 kΩ resistor (1%) | Load resistor |
| Scaling resistor pair (TBD) | Set divider ratio after measuring sensor R-range |
| Breadboard + jumper wires | |
| USB-A to micro-B cable | Programming + UART |
| 5V supply (can use USB 5V rail or external) | Sensor power |
| Multimeter | **Required** before connecting sensor to FPGA |

---

## Critical Safety Step — Read Before Connecting Anything

> The JXADC analog inputs are rated **0–1 V maximum**.
> Connecting more than 1 V will permanently damage the XADC input cell.

**Mandatory pre-connection checklist:**
1. Build sensor + 10kΩ + scaling divider on breadboard.
2. Power with 5 V, measure `V_out1` (junction of sensor and 10kΩ) in clean air and under breath.
3. Measure `V_out2` (output of scaling divider). It **must** stay below 0.9 V under all conditions.
4. Only after multimeter-confirming step 3, connect to JXADC.

---

## Analog Front-End

```
5V ──[Gas Sensor Rs]──┬──[R_load = 10kΩ]── GND
                      │
                    V_out1  (0–5V range, depends on Rs)
                      │
              ┌────[Ra]────┬── GND
              │            │
              │          V_out2  (0–1V, sized by Ra/Rb ratio)
              └────────────┘
                    [Rb]
```

**Divider math:**

```
V_out1 = 5V × (R_load / (Rs + R_load))
V_out2 = V_out1 × (Rb / (Ra + Rb))

Choose Ra, Rb so that V_out2_max ≈ 0.8V
i.e. Rb/(Ra+Rb) ≈ 0.8 / V_out1_max
```

After measuring V_out1 range, compute Ra and Rb using standard E24 values.

---

## JXADC Wiring (Nexys 4 DDR)

Default configuration uses **VAUXP[6] / VAUXN[6]** → JXADC header pins JA1 / JA7.

| JXADC Pin | Signal | Connect to |
|-----------|--------|------------|
| JA1 (pin 1) | VAUXP6 | V_out2 (scaled analog) |
| JA7 (pin 7) | VAUXN6 | GND (analog reference) |
| GND | Board GND | Circuit GND |

> Verify pin mapping in the Nexys 4 DDR Reference Manual, Table 15 before connecting.

---

## Building

### Prerequisites
- Vivado 2023.x (or later) with Artix-7 device support
- Python 3.x with `pyserial`, `pandas`, `matplotlib` (for PC scripts)

### Create Vivado Project
```tcl
# In Vivado Tcl Console:
source fpga/scripts/create_project.tcl
```

### Program Board
```tcl
source fpga/scripts/program.tcl
```

---

## Board Controls

| Control | Function |
|---------|----------|
| `CPU_RESETN` (active-low) | System reset |
| `BTNC` (center button) | Capture baseline (clean-air reference) |
| `SW[0]` | Display mode: 0 = sensitivity %, 1 = raw ΔR code |
| `LED16_R` | Red = sensor warming up (3 min timer) |
| `LED16_G` | Green = warm-up done, ready to baseline |
| `LED[7:0]` | Bar graph of raw ADC code |

---

## UART Data Format

Baud rate: **115200, 8N1**

Each frame (sent every 100 ms by default):
```
NNNNNN,RGAS,RAIR,DDDD,SSSS\r\n
  │      │    │    │    └── Sensitivity × 100 (signed integer, e.g. -1234 = -12.34%)
  │      │    │    └─────── Delta (R_gas - R_air, signed)
  │      │    └──────────── Baseline ADC code (12-bit, 0-4095)
  │      └───────────────── Live ADC code (12-bit, 0-4095)
  └──────────────────────── Sample counter (wraps at 999999)
```

---

## PC Logging

```bash
# Live logging to CSV:
python3 pc/gas_logger.py --port /dev/ttyUSB1 --output gas_log.csv

# Offline plot:
python3 pc/plot_sensitivity.py --input gas_log.csv
```

---

## Directory Structure

```
fpga/
  src/                     # Verilog RTL source files
  constraints/             # XDC pin/timing constraints
  sim/                     # Testbenches
  scripts/                 # Vivado TCL scripts
pc/
  gas_logger.py            # pyserial real-time logger
  plot_sensitivity.py      # Matplotlib offline analysis
```

---

## Sensor Warm-Up Note

MOx-type resistive gas sensors require **3–5 minutes** to stabilize after power-on.
Wait for `LED16_G` to turn green before pressing `BTNC` to capture a clean-air baseline.
Taking a baseline before warm-up will result in a drifting reference.
