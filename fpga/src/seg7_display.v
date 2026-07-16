// =============================================================================
// Gas Sensing System — 8-Digit 7-Segment Multiplexed Display Driver
// Board:  Nexys 4 DDR / Artix-7 XC7A100T (8 shared-anode digits)
// Target: Vivado 2023.x
//
// Refresh rate: 1 kHz per digit.
//   At 100 MHz clock, digit period = 100_000_000 / (8 × 1000) = 12_500 cycles
//
// Display modes (SW[0]):
//   0 → Sensitivity %: sign + 5 digits (e.g. "-012.34")
//       Digit 7 (leftmost): dash (−) if negative, blank if positive
//       Digits 6–2: integer and fractional parts of sensitivity
//       Digits 1–0: blank
//   1 → Raw ΔR code: sign + 4 hex digits
//       Digit 7 (leftmost): dash (−) if negative, blank if positive
//       Digits 6–3: 4 nibbles of |delta|
//       Digits 2–0: blank
//
// All anodes and segments are ACTIVE-LOW on Nexys 4 DDR.
// =============================================================================

`timescale 1ns / 1ps

module seg7_display (
    input  wire        clk,
    input  wire        rst,
    // Data inputs
    input  wire [12:0] delta,        // Signed 13-bit raw ΔR
    input  wire [15:0] sensitivity,  // Signed 16-bit, value × 100 (e.g. -1234 = -12.34%)
    input  wire        baseline_valid,
    input  wire        mode,         // SW[0]: 0 = sensitivity, 1 = delta hex
    // 7-segment outputs (active-low)
    output reg  [7:0]  an,           // Digit enables (active-low, AN[7] = leftmost)
    output reg  [6:0]  seg,          // {CA,CB,CC,CD,CE,CF,CG}
    output reg         dp            // Decimal point (active-low)
);

    // -------------------------------------------------------------------------
    // Refresh divider: 12500 cycles per digit, 8 digits → 8 kHz digit select
    // -------------------------------------------------------------------------
    localparam REFRESH_DIVIDER = 12_500;
    reg [13:0] refresh_cnt;
    reg [2:0]  digit_sel;    // 0–7 (0 = rightmost AN[0], 7 = leftmost AN[7])

    always @(posedge clk) begin
        if (rst) begin
            refresh_cnt <= 14'd0;
            digit_sel   <= 3'd0;
        end else if (refresh_cnt == REFRESH_DIVIDER - 1) begin
            refresh_cnt <= 14'd0;
            digit_sel   <= digit_sel + 1'b1;
        end else begin
            refresh_cnt <= refresh_cnt + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Segment decoder instance
    // -------------------------------------------------------------------------
    reg  [3:0] digit_val;
    wire [6:0] seg_decoded;

    seg7_decoder u_dec (
        .digit (digit_val),
        .seg   (seg_decoded)
    );

    // -------------------------------------------------------------------------
    // Special segment patterns
    // -------------------------------------------------------------------------
    localparam SEG_DASH  = 7'b111_1110;  // Only middle bar (g) on
    localparam SEG_BLANK = 7'b111_1111;  // All off

    // -------------------------------------------------------------------------
    // Sensitivity decomposition (unsigned magnitude + sign)
    // sensitivity_abs = |sensitivity|, max value meaningful here is ~9999 (99.99%)
    // -------------------------------------------------------------------------
    wire        sens_negative;
    wire [15:0] sensitivity_abs;

    assign sens_negative    = sensitivity[15];
    assign sensitivity_abs  = sens_negative ? (~sensitivity + 1'b1) : sensitivity;

    // BCD-ish decomposition: sensitivity_abs is value × 100
    // Display as:  [sign] [d4][d3][d2].[d1][d0]
    //              where the number is sensitivity_abs / 100 . sensitivity_abs % 100
    wire [3:0] s_d4 = (sensitivity_abs / 10000) % 10;   // tens of percent
    wire [3:0] s_d3 = (sensitivity_abs / 1000)  % 10;
    wire [3:0] s_d2 = (sensitivity_abs / 100)   % 10;   // units of percent
    wire [3:0] s_d1 = (sensitivity_abs / 10)    % 10;   // tenths
    wire [3:0] s_d0 = (sensitivity_abs)          % 10;   // hundredths

    // -------------------------------------------------------------------------
    // Delta decomposition (hex nibbles, unsigned magnitude)
    // -------------------------------------------------------------------------
    wire        delta_negative;
    wire [11:0] delta_abs;

    assign delta_negative = delta[12];
    assign delta_abs      = delta_negative ? (~delta[11:0] + 1'b1) : delta[11:0];

    wire [3:0] d_n3 = delta_abs[11:8];
    wire [3:0] d_n2 = delta_abs[7:4];
    wire [3:0] d_n1 = delta_abs[3:0];

    // -------------------------------------------------------------------------
    // Mux digit content and control signals
    // -------------------------------------------------------------------------
    reg  is_dp;     // Should decimal point be on for this digit?
    reg  is_dash;   // Should a dash be shown?
    reg  is_blank;  // Should this digit be blank?

    always @(*) begin
        // Defaults
        digit_val = 4'h0;
        is_dp     = 1'b0;
        is_dash   = 1'b0;
        is_blank  = 1'b0;

        if (!baseline_valid) begin
            // Before baseline: show dashes everywhere
            is_dash = 1'b1;
        end else if (!mode) begin
            // Mode 0: Sensitivity %
            // Digits: [7=sign][6=s_d4][5=s_d3][4=s_d2 + dp][3=s_d1][2=s_d0][1=blank][0=blank]
            case (digit_sel)
                3'd7: begin is_dash = sens_negative; is_blank = !sens_negative; end
                3'd6: begin digit_val = s_d4; end
                3'd5: begin digit_val = s_d3; end
                3'd4: begin digit_val = s_d2; is_dp = 1'b1; end  // decimal point
                3'd3: begin digit_val = s_d1; end
                3'd2: begin digit_val = s_d0; end
                3'd1: begin is_blank = 1'b1; end
                3'd0: begin is_blank = 1'b1; end
                default: is_blank = 1'b1;
            endcase
        end else begin
            // Mode 1: Raw ΔR hex
            // Digits: [7=sign][6=blank][5=d_n3][4=d_n2][3=d_n1][2=d_n0 part of abs][1=blank][0=blank]
            case (digit_sel)
                3'd7: begin is_dash = delta_negative; is_blank = !delta_negative; end
                3'd6: begin is_blank = 1'b1; end
                3'd5: begin digit_val = d_n3; end
                3'd4: begin digit_val = d_n2; end
                3'd3: begin digit_val = d_n1; end
                3'd2: begin digit_val = delta_abs[3:0]; end
                3'd1: begin is_blank = 1'b1; end
                3'd0: begin is_blank = 1'b1; end
                default: is_blank = 1'b1;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Register outputs (avoid glitches on anode/segment simultaneously)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            an  <= 8'hFF;   // All off (active-low)
            seg <= SEG_BLANK;
            dp  <= 1'b1;
        end else begin
            // Enable only the current digit (active-low → invert one-hot)
            an <= ~(8'h01 << digit_sel);

            if (is_dash)       seg <= SEG_DASH;
            else if (is_blank) seg <= SEG_BLANK;
            else               seg <= seg_decoded;

            dp <= ~is_dp;   // active-low
        end
    end

endmodule
