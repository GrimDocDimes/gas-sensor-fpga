// =============================================================================
// Gas Sensing System — Button Debouncer + Rising-Edge Detector
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
// Target: Vivado 2023.x
//
// Two-stage synchronizer → N-ms counter debounce → single-cycle edge pulse.
// Parameters:
//   CLK_FREQ    — system clock frequency in Hz (default 100 MHz)
//   DEBOUNCE_MS — debounce window in milliseconds (default 20 ms)
// =============================================================================

`timescale 1ns / 1ps

module debounce #(
    parameter CLK_FREQ    = 100_000_000,
    parameter DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire rst,
    input  wire btn_in,        // Raw (possibly noisy) button input
    output wire btn_out,       // Debounced level
    output wire btn_rising     // Single-cycle pulse on rising edge
);

    // -------------------------------------------------------------------------
    // Debounce counter bit-width and threshold
    // -------------------------------------------------------------------------
    localparam COUNTER_MAX = (CLK_FREQ / 1000) * DEBOUNCE_MS - 1;
    localparam CTR_W       = $clog2(COUNTER_MAX + 1);

    // -------------------------------------------------------------------------
    // 2-FF synchronizer (metastability protection)
    // -------------------------------------------------------------------------
    reg sync0, sync1;
    always @(posedge clk) begin
        if (rst) begin
            sync0 <= 1'b0;
            sync1 <= 1'b0;
        end else begin
            sync0 <= btn_in;
            sync1 <= sync0;
        end
    end

    // -------------------------------------------------------------------------
    // Counter-based debounce
    // -------------------------------------------------------------------------
    reg [CTR_W-1:0] counter;
    reg             debounced;

    always @(posedge clk) begin
        if (rst) begin
            counter   <= {CTR_W{1'b0}};
            debounced <= 1'b0;
        end else begin
            if (sync1 != debounced) begin
                // Input changed — start/restart the counter
                if (counter == COUNTER_MAX) begin
                    debounced <= sync1;    // Stable long enough — accept it
                    counter   <= {CTR_W{1'b0}};
                end else begin
                    counter <= counter + 1'b1;
                end
            end else begin
                counter <= {CTR_W{1'b0}};  // Input matches output — reset counter
            end
        end
    end

    // -------------------------------------------------------------------------
    // Rising-edge detector
    // -------------------------------------------------------------------------
    reg debounced_prev;
    always @(posedge clk) begin
        if (rst) debounced_prev <= 1'b0;
        else     debounced_prev <= debounced;
    end

    assign btn_out    = debounced;
    assign btn_rising = debounced & ~debounced_prev;

endmodule
