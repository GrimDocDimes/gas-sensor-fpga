// =============================================================================
// Gas Sensing System — Baseline Capture & Delta / Sensitivity Logic
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
// Target: Vivado 2023.x
//
// On btn_capture rising edge: latch current ADC code as R_air (baseline).
// On every adc_valid:         latch ADC code as R_gas (live reading).
//
// Computes:
//   delta       = R_gas - R_air       (13-bit signed, can be negative)
//   sensitivity = (delta * 100) / R_air  (Q8 signed fixed-point × 100)
//
// Divider:
//   USE_DIVIDER_IP = 1  → expects div_gen_0 IP instantiation (Vivado LogiCORE)
//                         numerator:   13-bit signed
//                         denominator: 12-bit unsigned (R_air)
//                         output:      signed quotient, ~17-cycle latency
//   USE_DIVIDER_IP = 0  → simple non-restoring shift-subtract (slower, no IP dep)
//
// =============================================================================

`timescale 1ns / 1ps

module baseline_delta #(
    parameter USE_DIVIDER_IP = 0    // 0 = shift-subtract, 1 = Vivado IP
) (
    input  wire        clk,
    input  wire        rst,
    // ADC feed
    input  wire [11:0] adc_code,
    input  wire        adc_valid,
    // Baseline capture trigger (single-cycle pulse from debouncer)
    input  wire        btn_capture,
    // Outputs
    output reg  [11:0] r_air,           // Latched baseline
    output reg  [11:0] r_gas,           // Latest live reading
    output reg  [12:0] delta,           // Signed: R_gas − R_air
    output reg  [15:0] sensitivity,     // Signed, scaled × 100
    output reg         baseline_valid,  // Goes high once R_air has been set
    output reg         result_valid     // Pulses when sensitivity is updated
);

    // -------------------------------------------------------------------------
    // Latch baseline on button press
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            r_air          <= 12'h0;
            baseline_valid <= 1'b0;
        end else if (btn_capture && adc_valid) begin
            r_air          <= adc_code;
            baseline_valid <= 1'b1;
        end else if (btn_capture && baseline_valid) begin
            // Allow re-latching with last known good adc_code
            r_air          <= r_gas;
            baseline_valid <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Track live ADC reading
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)         r_gas <= 12'h0;
        else if (adc_valid) r_gas <= adc_code;
    end

    // -------------------------------------------------------------------------
    // Compute delta (signed 13-bit)
    // -------------------------------------------------------------------------
    reg [12:0] delta_next;
    always @(posedge clk) begin
        if (rst) begin
            delta        <= 13'sh0;
            result_valid <= 1'b0;
        end else if (adc_valid && baseline_valid) begin
            delta_next   = {1'b0, adc_code} - {1'b0, r_air};  // sign-extend to 13b
            delta        <= delta_next;
            result_valid <= 1'b1;
        end else begin
            result_valid <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Sensitivity = (delta × 100) / R_air
    // -------------------------------------------------------------------------
    generate
        if (USE_DIVIDER_IP) begin : gen_ip_div
            // ------------------------------------------------------------------
            // Vivado Divider IP (div_gen_0)
            // Configure in IP Catalog:
            //   Algorithm:  Non-Restoring
            //   Dividend:   13-bit signed  (delta × 100, i.e. sign-extend to 20-bit)
            //   Divisor:    12-bit unsigned (r_air)
            //   Latency:    ~17 cycles (pipelined)
            //   Remainder:  optional
            // ------------------------------------------------------------------
            wire [19:0] dividend;
            wire [11:0] divisor;
            wire [19:0] quotient;
            wire        div_valid_out;

            // Scale numerator: delta × 100 (delta is 13-bit signed → extend to 20b)
            assign dividend = {{7{delta[12]}}, delta} * 20'sd100;
            assign divisor  = r_air;

            reg div_valid_in;
            always @(posedge clk) div_valid_in <= result_valid;

            div_gen_0 u_divider (
                .aclk                   (clk),
                .s_axis_dividend_tdata  (dividend),
                .s_axis_dividend_tvalid (div_valid_in),
                .s_axis_dividend_tready (),
                .s_axis_divisor_tdata   (divisor),
                .s_axis_divisor_tvalid  (div_valid_in),
                .s_axis_divisor_tready  (),
                .m_axis_dout_tdata      (quotient),
                .m_axis_dout_tvalid     (div_valid_out)
            );

            always @(posedge clk) begin
                if (rst)             sensitivity <= 16'h0;
                else if (div_valid_out) sensitivity <= quotient[15:0];
            end

        end else begin : gen_shift_div
            // ------------------------------------------------------------------
            // Simple iterative shift-subtract divider (no Vivado IP required)
            // Computes: |delta| × 100 / R_air, then re-applies sign
            // Latency: 20 clock cycles
            // Trigger: result_valid pulse from delta logic
            // ------------------------------------------------------------------
            localparam DIV_BITS = 20;

            reg  [DIV_BITS-1:0] remainder;
            reg  [DIV_BITS-1:0] divisor_r;
            reg  [DIV_BITS-1:0] quotient_r;
            reg  [4:0]          shift_cnt;    // 0..19
            reg                 busy_div;
            reg                 sign_flag;

            wire [DIV_BITS-1:0] numerator_abs;
            assign numerator_abs = delta[12]
                ? (~{7'b0, delta[11:0]} + 1'b1) * 100   // |delta| × 100 if negative
                : {7'b0, delta[11:0]} * 100;             // delta × 100 if positive

            always @(posedge clk) begin
                if (rst) begin
                    remainder   <= {DIV_BITS{1'b0}};
                    divisor_r   <= {DIV_BITS{1'b0}};
                    quotient_r  <= {DIV_BITS{1'b0}};
                    shift_cnt   <= 5'd0;
                    busy_div    <= 1'b0;
                    sign_flag   <= 1'b0;
                    sensitivity <= 16'h0;
                    result_valid <= 1'b0;   // override wire above in this branch

                end else if (result_valid && !busy_div && (r_air != 12'h0)) begin
                    // Start new division
                    remainder  <= {1'b0, numerator_abs[DIV_BITS-1:1]};
                    divisor_r  <= {1'b0, r_air, 7'b0};   // shift divisor left by 7
                    quotient_r <= {DIV_BITS{1'b0}};
                    shift_cnt  <= 5'd0;
                    sign_flag  <= delta[12];
                    busy_div   <= 1'b1;

                end else if (busy_div) begin
                    if (shift_cnt == 5'd19) begin
                        // Done — re-apply sign and emit
                        busy_div <= 1'b0;
                        sensitivity <= sign_flag
                            ? (~quotient_r[15:0] + 1'b1)
                            : quotient_r[15:0];
                        result_valid <= 1'b1;
                    end else begin
                        // Non-restoring step
                        if (remainder >= divisor_r) begin
                            remainder  <= remainder - divisor_r;
                            quotient_r <= {quotient_r[DIV_BITS-2:0], 1'b1};
                        end else begin
                            quotient_r <= {quotient_r[DIV_BITS-2:0], 1'b0};
                        end
                        divisor_r  <= {1'b0, divisor_r[DIV_BITS-1:1]};  // shift right
                        shift_cnt  <= shift_cnt + 1'b1;
                    end
                end else begin
                    result_valid <= 1'b0;
                end
            end
        end
    endgenerate

endmodule
