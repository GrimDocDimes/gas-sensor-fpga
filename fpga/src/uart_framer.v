// =============================================================================
// Gas Sensing System — UART ASCII Frame Builder
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
// Target: Vivado 2023.x
//
// Builds and transmits one ASCII frame per INTERVAL_CYCLES clock cycles.
// Frame format (all decimal, fixed-width, CR+LF terminated):
//
//   "NNNNNN,RGAS,RAIR,DDDDD,SSSSS\r\n"
//    ──────  ────  ────  ─────  ─────
//    sample  live  base  delta  sens (signed, e.g. -1234 = -12.34%)
//
// Total frame length ≤ 36 bytes.
//
// Parameters:
//   CLK_FREQ       — system clock in Hz
//   INTERVAL_CYCLES — cycles between frames (default 10M → 100ms at 100MHz)
// =============================================================================

`timescale 1ns / 1ps

module uart_framer #(
    parameter CLK_FREQ       = 100_000_000,
    parameter INTERVAL_CYCLES = 10_000_000   // 100 ms default
) (
    input  wire        clk,
    input  wire        rst,
    // Sensor data inputs (latched on each frame trigger)
    input  wire [11:0] r_gas,
    input  wire [11:0] r_air,
    input  wire [12:0] delta,        // signed
    input  wire [15:0] sensitivity,  // signed, × 100
    input  wire        baseline_valid,
    // UART byte stream interface
    output reg  [7:0]  uart_data,
    output reg         uart_valid,
    input  wire        uart_ready
);

    // -------------------------------------------------------------------------
    // Interval timer
    // -------------------------------------------------------------------------
    localparam TIMER_W = $clog2(INTERVAL_CYCLES);
    reg [TIMER_W-1:0] timer;
    reg               frame_trigger;

    always @(posedge clk) begin
        if (rst) begin
            timer         <= {TIMER_W{1'b0}};
            frame_trigger <= 1'b0;
        end else if (timer == INTERVAL_CYCLES - 1) begin
            timer         <= {TIMER_W{1'b0}};
            frame_trigger <= 1'b1;
        end else begin
            timer         <= timer + 1'b1;
            frame_trigger <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Sample counter
    // -------------------------------------------------------------------------
    reg [19:0] sample_cnt;   // Wraps at 1_000_000

    always @(posedge clk) begin
        if (rst) sample_cnt <= 20'd0;
        else if (frame_trigger) begin
            if (sample_cnt == 20'd999999) sample_cnt <= 20'd0;
            else                          sample_cnt <= sample_cnt + 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Frame assembly — build ASCII into a 36-byte buffer then stream it out
    //
    // We use a simple decimal encoder: pull digits by successive % 10 / / 10.
    // The buffer is filled MSB-first (leftmost digit first).
    // -------------------------------------------------------------------------
    localparam FRAME_LEN = 36;
    reg [7:0] frame [0:FRAME_LEN-1];
    reg [5:0] tx_ptr;      // Which byte we're currently sending (0..FRAME_LEN-1)
    reg       sending;     // We're in the middle of transmitting a frame

    // Helpers — convert 4-bit value to ASCII digit
    function [7:0] to_ascii;
        input [3:0] val;
        begin
            to_ascii = (val > 4'd9) ? 8'd0 : (8'd48 + {4'b0, val});
        end
    endfunction

    // Decimal encoder: 4-digit unsigned (0000–9999)
    task enc_dec4;
        input [13:0] val;
        input [5:0]  base_idx;
        begin
            frame[base_idx]   = to_ascii(val / 14'd1000 % 10);
            frame[base_idx+1] = to_ascii(val / 14'd100  % 10);
            frame[base_idx+2] = to_ascii(val / 14'd10   % 10);
            frame[base_idx+3] = to_ascii(val             % 10);
        end
    endtask

    // 6-digit unsigned
    task enc_dec6;
        input [19:0] val;
        input [5:0]  base_idx;
        begin
            frame[base_idx]   = to_ascii(val / 20'd100000 % 10);
            frame[base_idx+1] = to_ascii(val / 20'd10000  % 10);
            frame[base_idx+2] = to_ascii(val / 20'd1000   % 10);
            frame[base_idx+3] = to_ascii(val / 20'd100    % 10);
            frame[base_idx+4] = to_ascii(val / 20'd10     % 10);
            frame[base_idx+5] = to_ascii(val              % 10);
        end
    endtask

    // Signed 5-digit encoder (sign + 4 decimal digits)
    task enc_signed5;
        input [15:0] val;
        input [5:0]  base_idx;
        reg          is_neg;
        reg [15:0]   abs_val;
        begin
            is_neg  = val[15];
            abs_val = is_neg ? (~val + 1'b1) : val;
            frame[base_idx]   = is_neg ? 8'd45 : 8'd43;  // '-' or '+'
            frame[base_idx+1] = to_ascii(abs_val / 16'd1000 % 10);
            frame[base_idx+2] = to_ascii(abs_val / 16'd100  % 10);
            frame[base_idx+3] = to_ascii(abs_val / 16'd10   % 10);
            frame[base_idx+4] = to_ascii(abs_val             % 10);
        end
    endtask

    // -------------------------------------------------------------------------
    // Frame build + streaming state machine
    // -------------------------------------------------------------------------
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            sending    <= 1'b0;
            tx_ptr     <= 6'd0;
            uart_valid <= 1'b0;
            uart_data  <= 8'h0;
        end else begin
            uart_valid <= 1'b0;

            if (frame_trigger && !sending && baseline_valid) begin
                // Build the frame
                // "NNNNNN,RGAS,RAIR,DDDDD,SSSSS\r\n"
                //  0-5    7-10  12-15 17-21 23-27  28 29
                enc_dec6(sample_cnt,        6'd0);   // bytes 0–5: sample count
                frame[6]  = 8'd44;                   // ','
                enc_dec4({2'b0, r_gas},    6'd7);    // bytes 7–10: R_gas
                frame[11] = 8'd44;                   // ','
                enc_dec4({2'b0, r_air},    6'd12);   // bytes 12–15: R_air
                frame[16] = 8'd44;                   // ','
                enc_signed5({3'b0, delta}, 6'd17);   // bytes 17–21: delta (signed)
                frame[22] = 8'd44;                   // ','
                enc_signed5(sensitivity,   6'd23);   // bytes 23–27: sensitivity (signed)
                frame[28] = 8'd13;                   // '\r'
                frame[29] = 8'd10;                   // '\n'

                sending <= 1'b1;
                tx_ptr  <= 6'd0;

            end else if (sending) begin
                if (uart_ready && !uart_valid) begin
                    uart_data  <= frame[tx_ptr];
                    uart_valid <= 1'b1;
                    if (tx_ptr == 6'd29) begin
                        sending <= 1'b0;
                        tx_ptr  <= 6'd0;
                    end else begin
                        tx_ptr <= tx_ptr + 1'b1;
                    end
                end
            end
        end
    end

endmodule
