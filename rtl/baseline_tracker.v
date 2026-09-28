`timescale 1ns/1ps
// =============================================================================
// Module  : baseline_tracker
// Purpose : Per-channel exponential moving average (EMA) baseline tracker.
//
// Algorithm (integer EMA, no multiplier required):
//   ema[n] = ema[n-1] + (R[n] - ema[n-1]) >> ALPHA_SHIFT
//           = ema[n-1] × (1 - 1/2^N) + R[n] × (1/2^N)
//   where N = alpha_shift (runtime-programmable via AXI-Lite, default 4)
//
// This is equivalent to a first-order IIR low-pass filter with:
//   α = 1/2^N  (α = 0.0625 for N=4 → time constant ≈ 16 samples)
//
// The signed difference (R - ema) is computed to handle both rising and
// falling resistance correctly, then arithmetic right-shifted.
//
// Cold-start behaviour:
//   On the first valid sample after reset or ctrl_reset_baseline, the EMA
//   is seeded with that first R value (avoids initial convergence tail).
//   Subsequent samples update normally.
//
// Inputs:
//   resist_in     — 32-bit resistance from resistance_calc (Ω, integer)
//   valid_in      — 1-cycle pulse: resist_in is valid
//   alpha_shift   — EMA time constant N (α = 1/2^N); runtime register
//   reset_base    — 1-cycle pulse: re-seed EMA from next valid sample
//
// Outputs:
//   baseline_out  — 32-bit EMA baseline (Ω)
//   baseline_vld  — 1 when baseline_out contains a valid (seeded) value
//
// Synthesis notes:
//   - Arithmetic right-shift implemented with signed cast and >>>
//   - No latches; all paths assign baseline_reg
//   - Single clock domain, synchronous reset
// =============================================================================
module baseline_tracker #(
    parameter DATA_WIDTH   = 32,   // resistance data width (bits)
    parameter ALPHA_W      = 4     // width of alpha_shift port (supports N=1..15)
) (
    input  wire                   clk,
    input  wire                   rst_n,        // sync active-low reset

    // Data input
    input  wire [DATA_WIDTH-1:0]  resist_in,    // resistance sample
    input  wire                   valid_in,     // 1-cycle pulse: sample valid

    // Configuration (from AXI-Lite)
    input  wire [ALPHA_W-1:0]     alpha_shift,  // EMA shift N (α = 1/2^N)
    input  wire                   reset_base,   // 1-cycle pulse: re-seed EMA

    // Output
    output reg  [DATA_WIDTH-1:0]  baseline_out, // EMA baseline
    output reg                    baseline_vld  // 1 = baseline is seeded/valid
);

    // ── State ─────────────────────────────────────────────────────────────────
    reg seed_needed; // 1 = waiting for first sample to seed EMA

    // ── EMA accumulator ────────────────────────────────────────────────────────
    // Keep one extra guard bit to minimise rounding drift.
    // All arithmetic is done in signed domain to handle R < EMA correctly.
    reg signed [DATA_WIDTH:0] ema_reg; // extended by 1 bit for safety

    // ── Combinational difference and shift ────────────────────────────────────
    wire signed [DATA_WIDTH:0] resist_ext = {1'b0, resist_in}; // zero-extend to signed
    wire signed [DATA_WIDTH:0] ema_ext    = ema_reg;
    wire signed [DATA_WIDTH:0] diff       = resist_ext - ema_ext;
    // Arithmetic right-shift by alpha_shift (preserves sign)
    // Note: >>> on signed operands is arithmetic shift in Verilog-2001
    wire signed [DATA_WIDTH:0] diff_shift = diff >>> alpha_shift;
    wire signed [DATA_WIDTH:0] ema_next   = ema_ext + diff_shift;

    // ── Sequential logic ───────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            ema_reg      <= {(DATA_WIDTH+1){1'b0}};
            baseline_out <= {DATA_WIDTH{1'b0}};
            baseline_vld <= 1'b0;
            seed_needed  <= 1'b1;
        end else begin

            // ── Re-seed request from PS ────────────────────────────────────────
            if (reset_base) begin
                seed_needed  <= 1'b1;
                baseline_vld <= 1'b0;
            end

            // ── Process new sample ─────────────────────────────────────────────
            if (valid_in) begin
                if (seed_needed) begin
                    // Cold start / re-seed: initialise EMA to current sample
                    ema_reg      <= resist_ext;
                    baseline_out <= resist_in;
                    baseline_vld <= 1'b1;
                    seed_needed  <= 1'b0;
                end else begin
                    // Normal EMA update
                    ema_reg      <= ema_next;
                    // Clamp output to [0, 2^DATA_WIDTH-1] (guard against negative)
                    baseline_out <= ema_next[DATA_WIDTH] ? {DATA_WIDTH{1'b0}}
                                                         : ema_next[DATA_WIDTH-1:0];
                end
            end

        end
    end

endmodule
