`timescale 1ns/1ps
// =============================================================================
// Module  : alarm_controller
// Purpose : Alarm aggregation and state machine for gas sensor array.
//
// Collects alarm signals from multiple sources (dR/dt detectors and cross-
// channel fault detector) and drives a deterministic alarm output with:
//   - Registered (glitch-free) alarm_out
//   - Sticky latch (alarm stays active until PS acknowledges)
//   - Priority: roc_alarms > xfaults (any roc_alarm prevents ACK clearing)
//
// FSM (Moore — all outputs depend only on current state, no combinational paths):
//
//          rst_n=0
//             │
//             ▼
//          ┌──────┐
//    ┌────▶│ IDLE │◀──────────────────── (ACK received, no remaining alarm)
//    │     └──┬───┘
//    │        │ any alarm_in asserted
//    │        ▼
//    │     ┌────────┐
//    │     │ ACTIVE │  alarm_out=1, fault_out=current alarms
//    │     └──┬─────┘
//    │        │ alarm persists for > latch_cycles clocks
//    │        ▼
//    │     ┌─────────┐
//    │     │ LATCHED │  alarm_out=1 (sticky, even if inputs deassert)
//    │     └──┬──────┘
//    │        │ PS writes alarm_ack (CTRL[2])
//    │        ▼
//    │     ┌─────┐
//    └─────│ ACK │  alarm_out=0, clear latch — return to IDLE next cycle
//          └─────┘
//
// Why Moore (not Mealy)?
//   Mealy outputs would react combinationally to input changes → glitches on
//   alarm_out if connected to an LED or interrupt line.
//   Moore outputs are registered → clean transitions only on clock edges.
//
// Priority:
//   roc_alarms (rate-of-change) take priority over xfaults (cross-channel).
//   In ACK state: if any roc_alarm is still active, inhibit return to IDLE.
//
// Inputs:
//   roc_alarms[5:0]  — per-channel RoC alarms (from roc_detector × 6)
//   xfaults[5:0]     — per-channel cross-channel faults (from cross_channel_fault)
//   alarm_ack        — 1-cycle pulse from PS (CTRL[2] write)
//   latch_cycles     — cycles alarm must persist before latching (AXI-Lite reg)
//
// Outputs:
//   alarm_out        — global alarm (drives LED LD0)
//   fault_out[5:0]   — per-channel fault flags (readable via AXI STATUS)
//   alarm_active     — FSM is in ACTIVE state
//   alarm_latched    — FSM is in LATCHED state
// =============================================================================
module alarm_controller #(
    parameter NUM_CH    = 6,
    parameter LATCH_W   = 16       // width of latch_cycles counter
) (
    input  wire                  clk,
    input  wire                  rst_n,        // sync active-low reset

    // Alarm inputs
    input  wire [NUM_CH-1:0]     roc_alarms,   // rate-of-change alarms (per channel)
    input  wire [NUM_CH-1:0]     xfaults,      // cross-channel fault flags

    // Control
    input  wire                  alarm_ack,    // 1-cycle pulse: PS acknowledges alarm
    input  wire [LATCH_W-1:0]    latch_cycles, // alarm persistence before latch

    // Outputs (all registered — Moore FSM)
    output reg                   alarm_out,    // global alarm flag (LED / interrupt)
    output reg  [NUM_CH-1:0]     fault_out,    // per-channel active faults
    output reg                   alarm_active, // in ACTIVE state
    output reg                   alarm_latched // in LATCHED state
);

    // ── FSM state encoding ────────────────────────────────────────────────────
    localparam S_IDLE    = 2'd0;
    localparam S_ACTIVE  = 2'd1;
    localparam S_LATCHED = 2'd2;
    localparam S_ACK     = 2'd3;
    reg [1:0] state;

    // ── Alarm aggregation ─────────────────────────────────────────────────────
    wire any_alarm    = |roc_alarms | |xfaults;
    wire any_roc      = |roc_alarms;

    // ── Active-time counter (measures how long alarm has been asserted) ────────
    reg [LATCH_W-1:0] active_cnt;
    wire              cnt_expired = (active_cnt >= latch_cycles);

    // ── Latch register: captures alarm flags when latching ────────────────────
    reg [NUM_CH-1:0] fault_latch;   // sticky fault vector

    // ── Sequential FSM ────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            alarm_out     <= 1'b0;
            fault_out     <= {NUM_CH{1'b0}};
            alarm_active  <= 1'b0;
            alarm_latched <= 1'b0;
            active_cnt    <= {LATCH_W{1'b0}};
            fault_latch   <= {NUM_CH{1'b0}};
        end else begin
            case (state)

                // ── IDLE: no alarm ─────────────────────────────────────────────
                S_IDLE: begin
                    alarm_out     <= 1'b0;
                    alarm_active  <= 1'b0;
                    alarm_latched <= 1'b0;
                    active_cnt    <= {LATCH_W{1'b0}};

                    if (any_alarm) begin
                        // Capture which channels are faulting
                        fault_latch <= roc_alarms | xfaults;
                        fault_out   <= roc_alarms | xfaults;
                        state       <= S_ACTIVE;
                    end
                end

                // ── ACTIVE: alarm asserted, counting for latch ──────────────────
                S_ACTIVE: begin
                    alarm_out    <= 1'b1;
                    alarm_active <= 1'b1;
                    // Update fault_out with latest active alarms
                    fault_out    <= roc_alarms | xfaults;
                    // Update latch register with any newly triggered channels
                    fault_latch  <= fault_latch | roc_alarms | xfaults;
                    active_cnt   <= active_cnt + 1;

                    if (cnt_expired) begin
                        // Alarm has persisted long enough → latch it
                        state <= S_LATCHED;
                    end else if (!any_alarm) begin
                        // Alarm cleared before latch timeout → return to IDLE
                        // (transient alarm — logged in fault_latch for PS to read)
                        state <= S_IDLE;
                    end
                end

                // ── LATCHED: sticky alarm, waiting for PS acknowledgement ───────
                S_LATCHED: begin
                    alarm_out     <= 1'b1;
                    alarm_latched <= 1'b1;
                    // Keep fault_out frozen at latched state
                    fault_out     <= fault_latch;

                    if (alarm_ack) begin
                        state <= S_ACK;
                    end
                end

                // ── ACK: clear alarm for one cycle, then return to IDLE ─────────
                S_ACK: begin
                    alarm_out     <= 1'b0;
                    alarm_active  <= 1'b0;
                    alarm_latched <= 1'b0;
                    fault_out     <= {NUM_CH{1'b0}};
                    fault_latch   <= {NUM_CH{1'b0}};
                    active_cnt    <= {LATCH_W{1'b0}};

                    // If a roc_alarm is STILL active, go back to ACTIVE instead of IDLE
                    // (priority: cannot silence an ongoing RoC event via ACK alone)
                    if (any_roc) begin
                        fault_latch <= roc_alarms | xfaults;
                        fault_out   <= roc_alarms | xfaults;
                        state       <= S_ACTIVE;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
