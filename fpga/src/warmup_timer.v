// =============================================================================
// Gas Sensing System — Sensor Warm-Up Timer
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
// Target: Vivado 2023.x
//
// Counts WARMUP_SECONDS seconds from reset before asserting warmup_done.
// Drives LED indicators to signal status:
//   LED_RED  = 1 (warmup in progress), LED_GREEN = 0
//   LED_RED  = 0 (done),               LED_GREEN = 1
//
// Parameters:
//   CLK_FREQ       — system clock in Hz (default 100 MHz)
//   WARMUP_SECONDS — warm-up duration in seconds (default 180 s = 3 min)
// =============================================================================

`timescale 1ns / 1ps

module warmup_timer #(
    parameter CLK_FREQ       = 100_000_000,
    parameter WARMUP_SECONDS = 180
) (
    input  wire clk,
    input  wire rst,
    output wire warmup_done,
    output wire led_red,
    output wire led_green
);

    localparam WARMUP_CYCLES = CLK_FREQ * WARMUP_SECONDS;
    localparam CTR_W         = $clog2(WARMUP_CYCLES);

    reg [CTR_W-1:0] counter;
    reg             done;

    always @(posedge clk) begin
        if (rst) begin
            counter <= {CTR_W{1'b0}};
            done    <= 1'b0;
        end else if (!done) begin
            if (counter == WARMUP_CYCLES - 1) begin
                done <= 1'b1;
            end else begin
                counter <= counter + 1'b1;
            end
        end
    end

    assign warmup_done = done;
    assign led_red     = ~done;   // Active-high LED: red while warming up
    assign led_green   = done;    // Active-high LED: green when ready

endmodule
