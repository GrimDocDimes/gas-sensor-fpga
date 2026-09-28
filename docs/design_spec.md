# Design Specification
## FPGA-Based Multi-Channel Resistive Gas Sensor Acquisition System
### Target: PYNQ-Z2 (Zynq-7000 xc7z020clg400-1)

**Document Version:** 0.1 — Initial  
**Status:** For Review  
**Inspired by:** Enemali & Gibson (Applied Sciences, 2024); Choi et al. (Electronics, 2024)

---

## 1. Problem Statement

Design and verify a heterogeneous PYNQ-Z2–based acquisition architecture capable of:
- **Multi-channel sensor acquisition** — 6 resistive gas sensors via XADC (A0–A5)
- **Hardware signal processing** — resistance calculation and baseline tracking in PL
- **Rate-of-change (dR/dt) detection** — flag rapid resistance shifts in real time
- **Cross-channel fault isolation** — identify single misbehaving channels vs. global events
- **Deterministic alarm path** — PL alarm output with <2 clock cycle latency after threshold breach

---

## 2. System Context

```
                    ┌─────────────────────────────────────────────────────┐
                    │           PYNQ-Z2  (xc7z020clg400-1)               │
                    │                                                     │
  Gas Sensor Array  │  ┌──────────────────────────────────────────────┐  │
  (resistive, via   │  │            Programmable Logic (PL)           │  │
   voltage divider) │  │                                              │  │
                    │  │  XADC Wizard IP ──▶ DRP Read FSM             │  │
  A0 ──────────────▶│  │       │                │                     │  │
  A1 ──────────────▶│  │       ▼                ▼                     │  │
  A2 ──────────────▶│  │  [6 Sample Regs]  [Resistance Calc]          │  │
  A3 ──────────────▶│  │       │                │                     │  │
  A4 ──────────────▶│  │       ▼                ▼                     │  │
  A5 ──────────────▶│  │  [Baseline Tracker (EMA × 6)]                │  │
                    │  │       │                                      │  │
  10kΩ pullup       │  │       ▼                                      │  │
  (3.3V, each ch.)  │  │  [dR/dt Detector × 6]                        │  │
                    │  │       │                                      │  │
                    │  │       ▼                                      │  │
                    │  │  [Cross-Channel Fault Detector]               │  │
                    │  │       │                                      │  │
                    │  │       ▼                                      │  │
                    │  │  [Alarm Controller FSM] ──▶ ALARM_OUT        │  │
                    │  │       │                                      │  │
                    │  │  [AXI-Lite Slave Register Map]               │  │
                    │  └──────────────────┬───────────────────────────┘  │
                    │                     │ AXI-Lite (M_AXI_GP0, 32-bit) │
                    │  ┌──────────────────▼───────────────────────────┐  │
                    │  │        Processing System (PS)                │  │
                    │  │  ARM Cortex-A9 @ 666 MHz                     │  │
                    │  │  Python / PYNQ                               │  │
                    │  │  - Poll register map                         │  │
                    │  │  - Log resistance values                     │  │
                    │  │  - Live visualisation (Jupyter)              │  │
                    │  │  - Threshold configuration                   │  │
                    │  └──────────────────────────────────────────────┘  │
                    └─────────────────────────────────────────────────────┘
```

---

## 3. Interfaces & I/O

### 3.1 Hardware Interfaces

| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `vauxp[5:0]` | In | 6 | XADC VAUX positive inputs (A0–A5) |
| `vauxn[5:0]` | In | 6 | XADC VAUX negative inputs (tied to AGND) |
| `alarm_out` | Out | 1 | Active-high deterministic alarm (drives LED) |
| `fault_out[5:0]` | Out | 6 | Per-channel fault indicators |
| `clk` | In | 1 | 50 MHz FCLK_CLK0 from PS |
| `rst_n` | In | 1 | Active-low synchronous reset (from PS aresetn) |

### 3.2 XADC Arduino-to-VAUX Pin Mapping (PYNQ-Z2)

> **Verify against board schematic before synthesis.** These are from community XDC sources.

| Arduino Pin | XADC Channel | VAUXP Pin | VAUXN Pin |
|-------------|--------------|-----------|-----------|
| A0 | VAUX[1] | N15 | N16 |
| A1 | VAUX[9] | K15 | L15 |
| A2 | VAUX[6] | R17 | T17 |
| A3 | VAUX[15] | H15 | G15 |
| A4 | VAUX[5] | J14 | J15 |
| A5 | VAUX[13] | G14 | G15 |

### 3.3 AXI-Lite Interface

| Parameter | Value |
|-----------|-------|
| Address width | 32-bit |
| Data width | 32-bit |
| Base address | 0x43C0_0000 (assign in Vivado block design) |
| Burst | Single only |

---

## 4. Clock Domains & Reset Strategy

### 4.1 Clock Domains

| Domain | Source | Frequency | Used for |
|--------|--------|-----------|----------|
| `clk_pl` | FCLK_CLK0 (PS) | 50 MHz | All PL logic |
| `drp_clk` | Same as `clk_pl` | 50 MHz | XADC DRP bus |
| `adc_clk` | XADC internal | ~26 MHz | XADC conversion (internal, not exposed) |

**Single-clock design.** DRP results are synchronous to `clk_pl`. No CDC needed.

### 4.2 Reset Strategy

- **Type:** Synchronous, active-low (`rst_n`)
- **Source:** PS `peripheral_aresetn` from Processor System Reset IP
- **All registers reset to 0** on assertion
- No async reset — avoids metastability on Zynq fabric

---

## 5. Module Breakdown

### Module Hierarchy

```
gas_sensor_top
├── xadc_sequencer          (XADC Wizard IP wrapper + DRP read FSM)
├── resistance_calc [×6]    (fixed-point voltage-to-resistance)
├── baseline_tracker [×6]   (exponential moving average)
├── roc_detector [×6]       (rate-of-change |ΔR| > threshold)
├── cross_channel_fault     (inter-channel deviation detector)
├── alarm_controller        (Moore FSM, priority alarm aggregation)
└── axi_lite_regs           (AXI-Lite slave register file)
```

### `xadc_sequencer`
- Instantiates Xilinx XADC Wizard IP in **sequenced, continuous, unipolar** mode
- DRP Read FSM cycles: `WAIT_EOC → SEND_ADDR → WAIT_DRDY → CAPTURE`
- Outputs one `(adc_data[11:0], adc_ch[2:0], adc_valid)` pulse per channel per cycle

### `resistance_calc`
- Fixed-point only: `R = R_KNOWN × code / (CODE_FS − code)`
- Pipelined sequential restoring divider — **16-cycle latency**
- Output: 32-bit Ω (integer). Open circuit sentinel: `32'hFFFF_FFFF`

### `baseline_tracker`
- EMA: `ema += (R_in - ema) >>> ALPHA_SHIFT` (α = 1/2^N, parameterized)
- Cold-start: seeds EMA to first valid sample
- PS can force reset via CTRL register

### `roc_detector`
- `delta_R = |R_current - R_prev|`; `roc_alarm = (delta_R > ROC_THRESH)`
- Single-cycle latency after new sample

### `cross_channel_fault`
- Computes mean of 6 channels, then per-channel `|R_ch − mean| > XFAULT_THRESH`
- Distinguishes real gas event (all channels change) from single-channel fault
- FSM: `ACCUMULATE(6 cycles) → MEAN(1 cycle) → COMPARE(6 cycles) → OUTPUT`

### `alarm_controller` — Moore FSM

```
  rst_n=0
     │
     ▼
  ┌──────┐
  │ IDLE │◀──── ack & no alarms
  └──┬───┘
     │ any alarm asserted
     ▼
  ┌────────┐
  │ ACTIVE │  alarm_out=1, fault_out=ch_faults
  └──┬─────┘
     │ persists > LATCH_CYCLES
     ▼
  ┌────────┐
  │LATCHED │  alarm_out=1 (sticky)
  └──┬─────┘
     │ PS writes ACK
     ▼
  ┌─────┐
  │ ACK │  alarm_out=0, clear latch → IDLE (1 cycle)
  └─────┘
```

**Moore chosen:** registered outputs → no glitches on alarm_out line.

### `axi_lite_regs`
- Standard AXI-Lite slave, word-aligned, no FIFO
- Write channels: threshold registers + CTRL
- Read channels: all registers including status

---

## 6. AXI-Lite Register Map

| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x000–0x014 | `CH[0:5]_RAW` | R | Raw XADC 12-bit code per channel |
| 0x018–0x02C | `CH[0:5]_RESIST` | R | Resistance (Ω, 32-bit integer) |
| 0x030–0x044 | `CH[0:5]_BASE` | R | EMA baseline (Ω, 32-bit) |
| 0x048 | `STATUS` | R | [5:0]=new_data, [11:6]=roc_alarm, [17:12]=xfault, [18]=alarm_active, [19]=alarm_latched |
| 0x04C | `ALARM_LOG` | R | Sticky alarm log (cleared by ACK) |
| 0x050 | `CTRL` | R/W | [0]=enable, [1]=reset_baseline, [2]=alarm_ack, [9:4]=ch_mask |
| 0x054 | `CODE_FS` | R/W | XADC full-scale code (calibration, default 0xFFF) |
| 0x058 | `ROC_THRESH` | R/W | dR/dt threshold (Ω/sample, default 1000) |
| 0x05C | `XFAULT_THRESH` | R/W | Cross-channel deviation threshold (Ω, default 5000) |
| 0x060 | `ALPHA_SHIFT` | R/W | EMA shift N (α=1/2^N, default 4) |
| 0x064 | `LATCH_CYCLES` | R/W | Alarm latch duration (cycles, default 10) |

---

## 7. Fixed-Point Arithmetic

### Resistance
```
numerator   = R_KNOWN(14-bit) × code(12-bit)  → 26-bit
denominator = code_fs - code                   → 12-bit
R_out       = numerator / denominator          → 32-bit Ω
```

### EMA
```
ema_next = ema_reg + ((R_in - ema_reg) >>> ALPHA_SHIFT)
```
All 32-bit signed. Max R ~1 MΩ << 2^31. No overflow.

### RoC
```
delta_R = |R_current - R_prev|   (32-bit unsigned diff)
roc_alarm = (delta_R > ROC_THRESH)
```

---

## 8. Timing & Synthesis Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| Division latency (16 cycles) | Low | 26 Hz sample rate → 38 ms period; 16 cycles @ 50 MHz = 320 ns |
| XADC DRP timing at 50 MHz | Low | XADC Wizard IP meets 50 MHz on xc7z020-1 by characterization |
| Cross-channel mean combinational | Medium | Register outputs if WNS fails; add pipeline stage |
| EMA accumulator overflow | None | Max 1 MΩ, 32-bit register, no overflow |
| Latch inference risk | Medium | All always@* blocks must have complete case coverage; lint-check before synth |
| Missing reset paths | Medium | Enforce: every FF has `if(!rst_n)` branch |

---

## 9. Implementation Roadmap

### Phase 1 — RTL + Sim (now)
- [ ] `xadc_sequencer.v` + `tb_xadc_sequencer.v`
- [ ] `resistance_calc.v` + `tb_resistance_calc.v`
- [ ] `baseline_tracker.v` + `tb_baseline_tracker.v`
- [ ] `roc_detector.v` + `tb_roc_detector.v`
- [ ] `cross_channel_fault.v` + `tb_cross_channel_fault.v`
- [ ] `alarm_controller.v` + `tb_alarm_controller.v`
- [ ] `axi_lite_regs.v` + `tb_axi_lite_regs.v`
- [ ] `gas_sensor_top.v` + `tb_gas_sensor_top.v`

### Phase 2 — Vivado Block Design
- [ ] PS + custom IP + XADC Wizard + AXI interconnect
- [ ] XDC constraints (VAUX pins, clock, timing)
- [ ] Synthesis + implementation + timing closure

### Phase 3 — Python/PYNQ Driver
- [ ] `gas_sensor_monitor.ipynb`: register map driver + calibration cell
- [ ] Live 6-channel resistance plotting
- [ ] Alarm polling and logging

### Phase 4 — Hardware Bring-up
- [ ] Flash bitstream, verify XADC non-zero
- [ ] Single-channel R verification vs Python baseline
- [ ] 6-channel sweep + dR/dt + fault validation

---

## 10. Open Questions

1. **Exact VAUX pin mapping** — verify §3.2 from official PYNQ-Z2 Rev C schematic before generating XDC
2. **Cross-channel divide-by-6** — exact divider vs. shift-by-3 (÷8, ~33% error in mean): recommend exact for scientific accuracy
3. **Alarm output pin** — route to LD0 (on-board LED) or Arduino digital header?
4. **Sample rate target** — XADC default ~167 kSPS/channel is overkill for gas sensors (response time ~seconds); reducing to 1 kSPS saves power
5. **Interrupt vs. polling** — AXI-Lite polling chosen; add interrupt to PS GIC in Phase 2 if latency requirements tighten
