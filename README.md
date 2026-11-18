# FPGA Gas Sensor Acquisition System

This repository contains Verilog designs for acquiring and processing resistive metal-oxide (MOx) gas-sensor signals with Xilinx FPGAs. It has two related targets:

- **Primary design — PYNQ-Z2:** six-channel acquisition, resistance calculation, monitoring, and alarm logic for Zynq-7000 programmable logic.
- **Demonstration design — Nexys 4 DDR:** a single-channel interface with local display and UART output for bench use.

The time-critical path runs in FPGA logic: acquire an XADC sample, calculate resistance, track a baseline, detect a rapid change, compare channels, and issue a registered alarm. Live values and settings are available to PYNQ software over AXI4-Lite.

## How the primary design works

Each sensor is the lower resistor in a voltage divider with a known 10 kOhm pull-up resistor. The XADC samples the divider voltage, and the FPGA converts that sample to a resistance value.

```text
6 resistive sensors
        |
        v
XADC Wizard (continuous sequencer)
        |
        v
DRP reader -> 12-bit samples -> resistance calculator
                                      |
                         +------------+------------+
                         |                         |
                    EMA baseline             rate-of-change
                         |                         |
                         +------ cross-channel ----+
                                      |
                              alarm controller
                               |              |
                         LED/alarm out     AXI4-Lite
```

1. **Acquisition:** `xadc_sequencer` reads VAUX1, VAUX9, VAUX6, VAUX15, VAUX5, and VAUX13 after each XADC sequence. These are intended for PYNQ-Z2 Arduino inputs A0 through A5.
2. **Resistance calculation:** `resistance_calc` applies `R_sensor = R_known * code / (code_fs - code)` using integer arithmetic and a sequential restoring divider. A zero code is treated as a short-circuit condition; a code at or above the calibrated full-scale code is treated as open circuit.
3. **Baseline tracking:** `baseline_tracker` maintains an exponential moving average for each channel. Its configurable coefficient is `alpha = 1 / 2^N`.
4. **Rapid-change detection:** `roc_detector` compares the current and previous resistance values, asserting when their absolute difference exceeds the configured threshold.
5. **Cross-channel checking:** after enabled channels update, `cross_channel_fault` calculates their exact mean and flags channels that deviate from it by more than the configured threshold. This can separate one anomalous channel from a common response.
6. **Alarm handling:** `alarm_controller` combines detector flags in a Moore finite-state machine. The output is registered, can latch, and can be acknowledged through software.

## Performance and validation

The primary RTL uses a 50 MHz programmable-logic clock. The resistance divider has a fixed latency of 27 clock cycles: **540 ns at 50 MHz** from a normal input sample to its calculated resistance. This is much shorter than the intended gas-sensor sampling interval; the RTL documentation uses approximately 26 samples per second per channel as a representative rate. Actual sampling rate is determined by the XADC Wizard configuration.

The following self-checking Icarus Verilog testbenches pass:

| Testbench | Validates |
| --- | --- |
| `tb_resistance_calc.v` | Divider arithmetic and open/short handling |
| `tb_baseline_tracker.v` | Baseline seeding and EMA updates |
| `tb_roc_detector.v` | Per-sample resistance-change alarms |
| `tb_cross_channel_fault.v` | Mean/deviation fault detection |
| `tb_alarm_controller.v` | Alarm priority, latching, and acknowledgement |
| `tb_axi_lite_regs.v` | AXI4-Lite configuration and readback |

This is simulation evidence, not a hardware performance claim. No generated bitstream, timing-closure report, or PYNQ-Z2 hardware-validation result is included. Verify pin mapping, analog range, XADC configuration, calibration, synthesis timing, and end-to-end behavior before relying on the alarm path.

## Run the primary RTL simulations

Install Icarus Verilog, then run the suite from the `sim` directory:

```bash
cd sim
bash run_sims.sh
```

The runner writes generated `.vvp` files and logs to `sim/build/`.

## PYNQ-Z2 integration

### Hardware and interfaces

- Target: PYNQ-Z2, Zynq-7000 XC7Z020 programmable logic
- Inputs: six single-ended XADC auxiliary channels
- Logic clock: 50 MHz from the processing system
- Software interface: 32-bit AXI4-Lite slave; base address assigned in Vivado
- Alarm: active-high `alarm_out`, intended for LD0

Create an XADC Wizard IP block in Vivado using a DRP interface, continuous automatic sequencing, unipolar single-ended mode, and channels VAUX1/9/6/15/5/13. Connect the IP DRP ports to `gas_sensor_top` and expose the AXI4-Lite port through the processing-system interconnect.

The PYNQ-Z2 analog pin mapping in [the constraints file](constraints/pynqz2_gas_sensor.xdc) is a starting point only. Confirm it against the exact board revision and schematic before synthesis. The XADC input must also remain within the range permitted by the board and selected XADC configuration.

### Important AXI4-Lite registers

| Offset | Register | Purpose |
| --- | --- | --- |
| `0x000`–`0x014` | `CH[0:5]_RAW` | Raw 12-bit ADC codes |
| `0x018`–`0x02C` | `CH[0:5]_RESIST` | Calculated resistance in ohms |
| `0x030`–`0x044` | `CH[0:5]_BASE` | EMA baseline in ohms |
| `0x048` | `STATUS` | Detector and alarm status |
| `0x050` | `CTRL` | Enable, baseline reset, acknowledgement, channel mask |
| `0x054` | `CODE_FS` | Calibrated full-scale ADC code |
| `0x058` | `ROC_THRESH` | Resistance-change threshold, ohms/sample |
| `0x05C` | `XFAULT_THRESH` | Deviation-from-mean threshold, ohms |
| `0x060` | `ALPHA_SHIFT` | EMA coefficient shift `N` for `1 / 2^N` |
| `0x064` | `LATCH_CYCLES` | Alarm latch duration in clock cycles |

See [the complete design specification](docs/design_spec.md) for the module hierarchy, configuration defaults, bit fields, and implementation notes.

## Nexys 4 DDR demonstration design

The legacy design in `fpga/` targets a Nexys 4 DDR / Nexys A7-100T. It reads one XADC channel, captures a baseline with the center button, calculates change and sensitivity, displays the results on the seven-segment display, and transmits ASCII frames at 115200 baud.

The included warm-up timer is configured for 180 seconds. After warm-up, capture a clean-air baseline with the center button. This demonstration uses ADC-code-based sensitivity calculations and is separate from the six-channel PYNQ resistance pipeline.

Create its Vivado project with:

```bash
vivado -mode batch -source fpga/scripts/create_project.tcl
```

Review [the Nexys constraints](fpga/constraints/nexys4ddr_gas.xdc), especially the XADC pin assignments, before building hardware.

### UART logging and plots

Install the host tools:

```bash
python3 -m pip install pyserial pandas matplotlib
```

Log the UART stream and generate an offline plot:

```bash
python3 pc/gas_logger.py --port /dev/ttyUSB0 --output gas_log.csv
python3 pc/plot_sensitivity.py gas_log.csv --save sensitivity.png
```

The logger can auto-detect a port when `--port` is omitted. The expected frame is `sample_count,r_gas,r_air,delta,sensitivity_x100`.

## Repository layout

```text
rtl/                 Primary PYNQ-Z2 synthesizable Verilog modules
sim/                 Self-checking testbenches and simulation runner
constraints/         PYNQ-Z2 constraints
docs/design_spec.md  Primary-design specification and full register map
testpython/          PYNQ/Python calibration examples
fpga/                Legacy Nexys 4 DDR sources, constraints, and simulations
pc/                  UART CSV logger and offline plotting utility
```

## Notes for safe, reliable use

- The system measures electrical sensor response; it does not identify gas species or concentration by itself.
- Calibrate `CODE_FS`, the reference resistance, detector thresholds, and baseline behavior for the actual sensor, divider, supply, and environment.
- Do not assume a 3.3 V divider output is safe for an XADC input; verify the analog scaling first.
- Treat the alarm as a development feature until system-level hardware validation is complete.

## Further reading

- [Primary design specification](docs/design_spec.md)
- [PYNQ-Z2 constraints](constraints/pynqz2_gas_sensor.xdc)
- [PYNQ calibration example](testpython/read_a0.ipynb)
- [Nexys Vivado project script](fpga/scripts/create_project.tcl)
