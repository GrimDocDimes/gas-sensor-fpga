`timescale 1ns/1ps
// =============================================================================
// Module  : cross_channel_fault
// Purpose : Cross-channel deviation detector for 6-channel resistive sensor array.
//
// Computes the mean resistance across all active channels, then flags any
// single channel whose resistance deviates from the mean by more than a
// programmable threshold.
//
// Physical interpretation:
//   - If ALL channels change together   → real gas event  (no fault flagged)
//   - If ONE channel deviates from rest → sensor fault    (fault[ch] = 1)
//   This distinguishes true gas exposure from a broken/contaminated sensor.
//
// Architecture:
//   Multi-cycle sequential FSM:
//     ACCUM   (6 cycles) — sum all channel resistances
//     DIV     (variable) — compute mean via div_pipe (÷ num_active_channels)
//     COMPARE (6 cycles) — compare each channel against mean
//     OUTPUT  (1 cycle)  — register fault vector
//
// Division:
//   Uses div_pipe to compute exact mean (not approximate shift-by-3 ÷8).
//   This matters for fault detection accuracy near threshold boundaries.
//   Divisor = num_active_channels (1–6, controlled by ch_mask from CTRL register).
//
// Inputs:
//   resist[i]  — 32-bit resistance for channel i  (from resistance_calc × 6)
//   ch_valid   — 6-bit vector: bit i = 1 when resist[i] has a new valid sample
//   ch_mask    — 6-bit enable mask (from CTRL register; 0 = exclude from mean)
//   xf_thresh  — cross-channel threshold in Ω (from AXI-Lite)
//
// Outputs:
//   fault_out  — 6-bit fault vector (bit i = 1: channel i deviates from mean)
//   fault_vld  — 1-cycle pulse: fault_out updated
//   mean_out   — 32-bit mean resistance (diagnostic, readable via AXI)
//
// Timing:
//   Total latency per update: ~6 + (27 div cycles) + 6 + 1 = ~40 cycles = 800 ns
//   Compared to sample period ~38 ms: this is completely transparent.
//
// Synthesis notes:
//   - div_pipe instantiated for exact ÷N
//   - No latches
//   - Synchronous reset
// =============================================================================
module cross_channel_fault #(
    parameter NUM_CH     = 6,         // number of sensor channels
    parameter DATA_WIDTH = 32         // resistance data width
) (
    input  wire                        clk,
    input  wire                        rst_n,      // sync active-low reset

    // Per-channel resistance inputs (all valid simultaneously after acquisition)
    input  wire [DATA_WIDTH-1:0]       resist0,
    input  wire [DATA_WIDTH-1:0]       resist1,
    input  wire [DATA_WIDTH-1:0]       resist2,
    input  wire [DATA_WIDTH-1:0]       resist3,
    input  wire [DATA_WIDTH-1:0]       resist4,
    input  wire [DATA_WIDTH-1:0]       resist5,

    // Trigger: start a new cross-channel computation when high
    // (Top-level asserts this after all 6 channels have been updated)
    input  wire                        trigger,

    // Configuration
    input  wire [NUM_CH-1:0]           ch_mask,    // 1 = channel active in mean
    input  wire [DATA_WIDTH-1:0]       xf_thresh,  // deviation threshold (Ω)

    // Outputs
    output reg  [NUM_CH-1:0]           fault_out,  // per-channel fault flags
    output reg  [DATA_WIDTH-1:0]       mean_out,   // mean resistance (diagnostic)
    output reg                         fault_vld   // 1-cycle: fault_out updated
);

    // ── Localparams ───────────────────────────────────────────────────────────
    // Sum width: 6 × 32-bit = max 6×4294967295 ≈ 2^35. Use 35 bits for sum.
    localparam SUM_W  = DATA_WIDTH + 3; // +3 bits to fit 6× (log2(6)≈2.58)
    localparam CNT_W  = 3;              // channel counter: 0..5

    // ── FSM states ────────────────────────────────────────────────────────────
    localparam S_IDLE    = 3'd0;
    localparam S_ACCUM   = 3'd1;
    localparam S_WAIT_DIV= 3'd2;
    localparam S_COMPARE = 3'd3;
    localparam S_OUTPUT  = 3'd4;
    reg [2:0] state;

    // ── Registers ─────────────────────────────────────────────────────────────
    reg [SUM_W-1:0]    sum_reg;         // accumulator
    reg [DATA_WIDTH-1:0] mean_reg;      // computed mean
    reg [CNT_W-1:0]    ch_cnt;          // channel counter (0..5)
    reg [DATA_WIDTH-1:0] resist_latch [0:NUM_CH-1]; // snapshot of all channels
    reg [5:0]           fault_reg;      // computed fault vector
    reg [CNT_W-1:0]     num_active;     // count of active channels (denominator)
    reg [DATA_WIDTH-1:0] dev;           // deviation calculation helper

    // ── div_pipe interface ────────────────────────────────────────────────────
    // Divide SUM_W-bit sum by NUM_CH (≤6, fits in 3 bits)
    wire [SUM_W-1:0]  div_quotient;
    wire              div_valid;
    wire              div_bz;           // div_by_zero (guarded: num_active >= 1)
    reg               div_start;
    reg  [SUM_W-1:0]  div_dividend;
    reg  [2:0]        div_divisor;

    div_pipe #(
        .DIVIDEND_BITS (SUM_W),
        .DIVISOR_BITS  (3)
    ) u_mean_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .dividend    (div_dividend),
        .divisor     (div_divisor),
        .start       (div_start),
        .quotient    (div_quotient),
        .valid       (div_valid),
        .div_by_zero (div_bz)
    );

    // ── Helper: channel resistance MUX ────────────────────────────────────────
    // Returns resist[ch_cnt]
    reg [DATA_WIDTH-1:0] ch_r;
    always @(*) begin
        case (ch_cnt)
            3'd0: ch_r = resist_latch[0];
            3'd1: ch_r = resist_latch[1];
            3'd2: ch_r = resist_latch[2];
            3'd3: ch_r = resist_latch[3];
            3'd4: ch_r = resist_latch[4];
            3'd5: ch_r = resist_latch[5];
            default: ch_r = {DATA_WIDTH{1'b0}};
        endcase
    end

    // ── Sequential FSM ────────────────────────────────────────────────────────
    integer i;

    always @(posedge clk) begin
        // Default deassert
        div_start <= 1'b0;
        fault_vld <= 1'b0;

        if (!rst_n) begin
            state     <= S_IDLE;
            sum_reg   <= {SUM_W{1'b0}};
            mean_reg  <= {DATA_WIDTH{1'b0}};
            ch_cnt    <= {CNT_W{1'b0}};
            fault_reg <= {NUM_CH{1'b0}};
            fault_out <= {NUM_CH{1'b0}};
            mean_out  <= {DATA_WIDTH{1'b0}};
            num_active<= {CNT_W{1'b0}};
            div_dividend <= {SUM_W{1'b0}};
            div_divisor  <= 3'd1;
            for (i = 0; i < NUM_CH; i = i + 1)
                resist_latch[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            case (state)

                // ── IDLE: wait for trigger ─────────────────────────────────────
                S_IDLE: begin
                    if (trigger) begin
                        // Snapshot all channel resistances
                        resist_latch[0] <= resist0;
                        resist_latch[1] <= resist1;
                        resist_latch[2] <= resist2;
                        resist_latch[3] <= resist3;
                        resist_latch[4] <= resist4;
                        resist_latch[5] <= resist5;
                        // Count active channels
                        num_active <= ch_mask[0] + ch_mask[1] + ch_mask[2]
                                    + ch_mask[3] + ch_mask[4] + ch_mask[5];
                        sum_reg    <= {SUM_W{1'b0}};
                        ch_cnt     <= {CNT_W{1'b0}};
                        fault_reg  <= {NUM_CH{1'b0}};
                        state      <= S_ACCUM;
                    end
                end

                // ── ACCUM: add active channel resistances ──────────────────────
                S_ACCUM: begin
                    // Add this channel's resistance if it is active (ch_mask[ch_cnt])
                    if (ch_mask[ch_cnt])
                        sum_reg <= sum_reg + {{(SUM_W-DATA_WIDTH){1'b0}}, ch_r};

                    if (ch_cnt == NUM_CH-1) begin
                        // All channels summed; start division
                        // Guard: if num_active == 0, treat as 1 (shouldn't happen)
                        div_dividend <= sum_reg + ( ch_mask[ch_cnt]
                                        ? {{(SUM_W-DATA_WIDTH){1'b0}}, ch_r}
                                        : {SUM_W{1'b0}} );
                        div_divisor  <= (num_active == 0) ? 3'd1 : num_active;
                        div_start    <= 1'b1;
                        ch_cnt       <= {CNT_W{1'b0}};
                        state        <= S_WAIT_DIV;
                    end else begin
                        ch_cnt <= ch_cnt + 1;
                    end
                end

                // ── WAIT_DIV: wait for div_pipe to finish ──────────────────────
                S_WAIT_DIV: begin
                    if (div_valid) begin
                        // div_quotient is SUM_W bits; trim to DATA_WIDTH for mean
                        mean_reg <= div_quotient[DATA_WIDTH-1:0];
                        ch_cnt   <= {CNT_W{1'b0}};
                        state    <= S_COMPARE;
                    end
                end

                // ── COMPARE: per-channel deviation check ───────────────────────
                S_COMPARE: begin
                    if (ch_mask[ch_cnt]) begin
                        // |R[ch] - mean| > xf_thresh ?
                        dev = (ch_r >= mean_reg) ? (ch_r - mean_reg)
                                                  : (mean_reg - ch_r);
                        if (dev > xf_thresh)
                            fault_reg[ch_cnt] <= 1'b1;
                    end

                    if (ch_cnt == NUM_CH-1) begin
                        state <= S_OUTPUT;
                    end else begin
                        ch_cnt <= ch_cnt + 1;
                    end
                end

                // ── OUTPUT: register results ───────────────────────────────────
                S_OUTPUT: begin
                    fault_out <= fault_reg;
                    mean_out  <= mean_reg;
                    fault_vld <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
