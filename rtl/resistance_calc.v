`timescale 1ns/1ps
// =============================================================================
// Module  : resistance_calc
// Purpose : Convert a 12-bit XADC raw code to resistance (Ω) using the
//           voltage-divider formula, using fixed-point integer arithmetic only.
//
// Circuit topology (per channel):
//
//   3.3V ──[R_KNOWN]──┬──[R_SENSOR]── GND
//                     │
//                    A0  (XADC input, reads V_out)
//
// Formula:
//   V_out / V_supply = R_SENSOR / (R_KNOWN + R_SENSOR)
//   → R_SENSOR = R_KNOWN × code / (CODE_FS − code)
//
// Where:
//   code    = 12-bit XADC output (0..4095)
//   CODE_FS = calibration register (full-scale code ≡ code when A0 = V_supply)
//             Written by PS at startup (typical ~half of 4095 after internal
//             board-level scaling; from Python test: CODE_FS ≈ 2 × V_mid_code)
//   R_KNOWN = 10 000 Ω (top resistor, parameter)
//
// Fixed-point arithmetic:
//   numerator   = R_KNOWN × code        → max = 10000 × 4095 = 40 950 000 (26-bit)
//   denominator = CODE_FS − code        → max = 4095 (12-bit)
//   Uses div_pipe #(26, 12) → latency = 27 clock cycles @ 50 MHz = 540 ns
//   Compare to per-channel sample period ≈ 38 ms (26 Hz): latency is negligible.
//
// Special cases:
//   code == 0            → R = 32'h0000_0000 (short circuit sentinel)
//   code >= CODE_FS      → R = 32'hFFFF_FFFF (open circuit sentinel)
//   CODE_FS == 0         → R = 32'hFFFF_FFFF (invalid calibration guard)
//
// Latency: 27 clock cycles from valid_in to valid_out
//
// Synthesis notes:
//   - No latches
//   - No async reset
//   - div_pipe instantiated for the divider (synthesisable, no IP dependency)
// =============================================================================
module resistance_calc #(
    parameter R_KNOWN      = 10_000, // Ω — reference resistor value
    parameter CODE_WIDTH   = 12,     // XADC output width (bits)
    parameter RESULT_WIDTH = 32      // output resistance width (bits)
) (
    input  wire                     clk,
    input  wire                     rst_n,       // sync active-low reset

    // Calibration (written once by PS via AXI-Lite)
    input  wire [CODE_WIDTH-1:0]    code_fs,     // full-scale XADC code

    // Input sample
    input  wire [CODE_WIDTH-1:0]    code_in,     // raw 12-bit XADC code
    input  wire                     valid_in,    // 1-cycle pulse: code_in valid

    // Output result
    output reg  [RESULT_WIDTH-1:0]  resist_out,  // resistance in Ω
    output reg                      valid_out,   // 1-cycle pulse: resist_out valid
    output reg                      oc_flag,     // open-circuit flag (with valid_out)
    output reg                      sc_flag      // short-circuit flag (with valid_out)
);

    // ── Numerator width: R_KNOWN × max_code = 10000 × 4095 = 40950000 < 2^26 ─
    localparam NUM_W = 26;
    localparam DEN_W = CODE_WIDTH;  // 12

    // ── Pre-compute numerator: R_KNOWN × code_in ──────────────────────────────
    // This is a constant-coefficient multiply (R_KNOWN is a parameter).
    // Vivado/Quartus synthesise this into a dedicated DSP48 or LUT cascade.
    wire [NUM_W-1:0]    numerator;
    wire [DEN_W-1:0]    denominator;
    wire                div_start;
    wire                is_sc, is_oc;

    assign is_sc = (code_in == {CODE_WIDTH{1'b0}});
    assign is_oc = (code_fs == {CODE_WIDTH{1'b0}}) || (code_in >= code_fs);

    // Guarded numerator: R_KNOWN(14-bit) × code_in(12-bit) → 26-bit product
    // Explicit sizing avoids Verilog-2001 expression bit-select restriction.
    // Max product: 10000 × 4095 = 40,950,000 < 2^26. Safe to truncate to NUM_W.
    wire [13:0] r_known_w  = R_KNOWN[13:0];          // 14-bit: 10000 < 2^14
    wire [13:0] code_ext   = {{2{1'b0}}, code_in};   // zero-extend 12-bit to 14-bit
    wire [27:0] num_wide   = r_known_w * code_ext;   // 14×14 = 28-bit product
    assign numerator   = num_wide[NUM_W-1:0];         // take lower 26 bits (safe)
    assign denominator = code_fs - code_in;           // positive when code_in < code_fs

    // ── Special-case pipeline (match div_pipe latency) ─────────────────────────
    // We register is_sc/is_oc alongside the division so they arrive at the same
    // time as div_valid.  Shift register depth = DIVIDEND_BITS+1 cycles = 27.
    localparam DIV_LATENCY = NUM_W + 1; // = 27 cycles
    reg [DIV_LATENCY-1:0] sc_pipe, oc_pipe;

    always @(posedge clk) begin
        if (!rst_n) begin
            sc_pipe <= {DIV_LATENCY{1'b0}};
            oc_pipe <= {DIV_LATENCY{1'b0}};
        end else begin
            sc_pipe <= {sc_pipe[DIV_LATENCY-2:0], (valid_in & is_sc)};
            oc_pipe <= {oc_pipe[DIV_LATENCY-2:0], (valid_in & is_oc)};
        end
    end

    // ── Start div_pipe only for normal (non-SC, non-OC) samples ───────────────
    assign div_start = valid_in & ~is_sc & ~is_oc;

    // ── Division result ────────────────────────────────────────────────────────
    wire [NUM_W-1:0]  div_quotient;
    wire              div_valid;
    wire              div_by_zero;   // should never occur (guarded above)

    div_pipe #(
        .DIVIDEND_BITS (NUM_W),
        .DIVISOR_BITS  (DEN_W)
    ) u_div (
        .clk         (clk),
        .rst_n       (rst_n),
        .dividend    (numerator),
        .divisor     (denominator),
        .start       (div_start),
        .quotient    (div_quotient),
        .valid       (div_valid),
        .div_by_zero (div_by_zero)
    );

    // ── Output MUX: combine normal result with SC/OC sentinel values ───────────
    always @(posedge clk) begin
        // Default deassert
        valid_out <= 1'b0;
        oc_flag   <= 1'b0;
        sc_flag   <= 1'b0;

        if (!rst_n) begin
            resist_out <= {RESULT_WIDTH{1'b0}};
        end else begin
            if (div_valid) begin
                // Normal division result (not SC, not OC, guarded by div_start)
                resist_out <= {{(RESULT_WIDTH-NUM_W){1'b0}}, div_quotient};
                valid_out  <= 1'b1;
            end else if (sc_pipe[DIV_LATENCY-1]) begin
                // Short circuit: arrived after shift-register delay
                resist_out <= {RESULT_WIDTH{1'b0}};
                valid_out  <= 1'b1;
                sc_flag    <= 1'b1;
            end else if (oc_pipe[DIV_LATENCY-1]) begin
                // Open circuit: arrived after shift-register delay
                resist_out <= {RESULT_WIDTH{1'b1}};
                valid_out  <= 1'b1;
                oc_flag    <= 1'b1;
            end
        end
    end

endmodule
