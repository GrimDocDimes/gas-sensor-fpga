// =============================================================================
// Gas Sensing System — UART TX Byte Transmitter
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
// Target: Vivado 2023.x
//
// Standard 8N1 UART transmitter with ready/valid handshake.
// Identical interface and implementation to the MachinePulse reference.
//
// Parameters:
//   CLK_FREQ — system clock frequency in Hz
//   BAUD     — baud rate (default 115200)
//
// Interface:
//   data_in   [7:0]  — byte to transmit
//   data_valid        — assert high for one cycle to start transmission
//   tx_ready          — high when idle and ready to accept a new byte
//   tx                — UART serial output (idle-high)
// =============================================================================

`timescale 1ns / 1ps

module uart_tx #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD     = 115_200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data_in,
    input  wire       data_valid,
    output wire       tx_ready,
    output reg        tx
);

    localparam BIT_PERIOD = CLK_FREQ / BAUD;      // Cycles per bit (e.g. 868 at 100MHz/115200)
    localparam CTR_W      = $clog2(BIT_PERIOD);

    // -------------------------------------------------------------------------
    // State machine
    // -------------------------------------------------------------------------
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0]      state;
    reg [CTR_W-1:0] baud_cnt;
    reg [3:0]      bit_idx;   // 0–7 for data bits
    reg [7:0]      shift_reg;

    assign tx_ready = (state == S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state    <= S_IDLE;
            baud_cnt <= {CTR_W{1'b0}};
            bit_idx  <= 4'd0;
            shift_reg<= 8'h0;
            tx       <= 1'b1;   // Idle high
        end else begin
            case (state)

                S_IDLE: begin
                    tx <= 1'b1;
                    if (data_valid) begin
                        shift_reg <= data_in;
                        baud_cnt  <= {CTR_W{1'b0}};
                        state     <= S_START;
                    end
                end

                S_START: begin
                    tx <= 1'b0;   // Start bit
                    if (baud_cnt == BIT_PERIOD - 1) begin
                        baud_cnt <= {CTR_W{1'b0}};
                        bit_idx  <= 4'd0;
                        state    <= S_DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    tx <= shift_reg[0];   // LSB first
                    if (baud_cnt == BIT_PERIOD - 1) begin
                        baud_cnt  <= {CTR_W{1'b0}};
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 4'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    tx <= 1'b1;   // Stop bit
                    if (baud_cnt == BIT_PERIOD - 1) begin
                        baud_cnt <= {CTR_W{1'b0}};
                        state    <= S_IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
