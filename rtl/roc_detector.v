`timescale 1ns/1ps
// =============================================================================
// Module  : roc_detector
// Purpose : Per-channel rate-of-change (dR/dt) detector.
//
// Detects when the absolute change in resistance between consecutive samples
// exceeds a programmable threshold:
//
//   |R[n] - R[n-1]| > ROC_THRESH  →  roc_alarm = 1
//
// This flags rapid resistance shifts that may indicate a gas exposure event
// or a sensor fault (as opposed to slow, gradual environmental drift captured
// by the baseline tracker).
//
// Inputs:
//   resist_in  — 32-bit resistance sample from resistance_calc
//   valid_in   — 1-cycle pulse: resist_in is valid
//   roc_thresh — alarm threshold in Ω (from AXI-Lite register)
//
// Outputs:
//   roc_alarm  — level signal, HIGH when |ΔR| > roc_thresh
//                Updated every valid_in pulse; held between pulses.
//   delta_r    — 32-bit |ΔR| for each valid sample (diagnostic, readable via AXI)
//
// Note on OC/SC sentinels:
//   resistance_calc outputs 32'hFFFF_FFFF for open-circuit and 32'h0000_0000
//   for short-circuit.  A transition to/from these values will produce a
//   very large delta_r, causing a guaranteed roc_alarm.  The upstream fault
//   flags (oc_flag, sc_flag) in resistance_calc should be used for separate
//   fault classification; roc_alarm is for rate-of-change events only.
//
// Synthesis notes:
//   - Pure combinational delta_r + registered comparison
//   - No latches, no async reset
// =============================================================================
module roc_detector #(
    parameter DATA_WIDTH = 32
) (
    input  wire                   clk,
    input  wire                   rst_n,       // sync active-low reset

    // Data input
    input  wire [DATA_WIDTH-1:0]  resist_in,   // latest resistance sample
    input  wire                   valid_in,    // 1-cycle pulse: sample valid

    // Configuration
    input  wire [DATA_WIDTH-1:0]  roc_thresh,  // |ΔR| alarm threshold (Ω)

    // Outputs
    output reg  [DATA_WIDTH-1:0]  delta_r,     // |R[n] - R[n-1]| (registered)
    output reg                    roc_alarm    // 1 = rate-of-change exceeds threshold
);

    // ── Previous sample register ───────────────────────────────────────────────
    reg [DATA_WIDTH-1:0] r_prev;
    reg                  r_prev_valid; // 1 = r_prev holds a valid previous sample

    // ── Combinational: absolute difference ────────────────────────────────────
    // Both operands are unsigned. Subtract smaller from larger to get |ΔR|.
    wire [DATA_WIDTH-1:0] delta_comb = (resist_in >= r_prev)
                                       ? (resist_in - r_prev)
                                       : (r_prev - resist_in);

    // ── Sequential logic ───────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            r_prev       <= {DATA_WIDTH{1'b0}};
            r_prev_valid <= 1'b0;
            delta_r      <= {DATA_WIDTH{1'b0}};
            roc_alarm    <= 1'b0;
        end else if (valid_in) begin
            if (r_prev_valid) begin
                // Compute delta and compare to threshold
                delta_r   <= delta_comb;
                roc_alarm <= (delta_comb > roc_thresh);
            end else begin
                // First sample after reset: no previous sample to diff against
                delta_r   <= {DATA_WIDTH{1'b0}};
                roc_alarm <= 1'b0;
            end
            // Always update previous sample and mark it valid
            r_prev       <= resist_in;
            r_prev_valid <= 1'b1;
        end
    end

endmodule
