`timescale 1ns/1ps
// =============================================================================
// Module  : div_pipe
// Purpose : Sequential restoring unsigned integer divider.
//           Computes quotient = dividend / divisor.
//           Not pipelined — accepts one operation at a time.
//           Suitable for gas-sensor resistance calculation where the per-channel
//           sample rate (~26 Hz) is far below the 50 MHz system clock.
//
// Latency : DIVIDEND_BITS + 1 clock cycles after start pulse
// Throughput: one division per DIVIDEND_BITS+2 cycles (start→BUSY→IDLE)
//
// Interface (valid/start handshake):
//   - Assert 'start' for exactly one cycle with valid dividend/divisor.
//   - 'valid' pulses high for exactly one cycle when quotient is ready.
//   - Do not assert 'start' again while the module is BUSY (no backpressure
//     protection — caller must wait for 'valid' before issuing next start).
//
// Special cases:
//   - divisor == 0 : quotient = all-ones (saturation), div_by_zero = 1
//
// Synthesis notes:
//   - Synchronous active-low reset only (no async)
//   - No latches: every always block drives all outputs in every path
//   - Full case coverage with default branch
// =============================================================================
module div_pipe #(
    parameter DIVIDEND_BITS = 26,   // Width of dividend
    parameter DIVISOR_BITS  = 12    // Width of divisor
) (
    input  wire                       clk,
    input  wire                       rst_n,       // sync active-low reset

    // Input channel (present start pulse with valid dividend/divisor)
    input  wire [DIVIDEND_BITS-1:0]   dividend,
    input  wire [DIVISOR_BITS-1:0]    divisor,
    input  wire                       start,       // 1-cycle start pulse

    // Output channel
    output reg  [DIVIDEND_BITS-1:0]   quotient,    // result = dividend / divisor
    output reg                        valid,       // 1-cycle pulse: quotient ready
    output reg                        div_by_zero  // asserted with valid if divisor==0
);

    // ── State ─────────────────────────────────────────────────────────────────
    localparam S_IDLE = 1'b0, S_BUSY = 1'b1;
    reg state;

    // ── Counter: tracks remaining steps (DIVIDEND_BITS steps total) ────────────
    localparam CNT_W = $clog2(DIVIDEND_BITS);
    reg [CNT_W-1:0] cnt;

    // ── Working registers ──────────────────────────────────────────────────────
    reg [DIVIDEND_BITS-1:0] dvd_shift;   // dividend shift register (MSB-first)
    reg [DIVIDEND_BITS-1:0] quot_acc;    // quotient accumulator (built LSB-last)
    reg [DIVISOR_BITS-1:0]  dvr_latch;   // divisor latched at start (immutable)
    reg [DIVISOR_BITS:0]    partial;     // partial remainder (+1 bit for sign)

    // ── Combinational: one restoring division step ────────────────────────────
    // Shift partial left and bring in MSB of current dvd_shift
    wire [DIVISOR_BITS:0] p_shift = {partial[DIVISOR_BITS-1:0], dvd_shift[DIVIDEND_BITS-1]};
    // Attempt subtraction of divisor (zero-padded to DIVISOR_BITS+1)
    wire [DIVISOR_BITS:0] p_sub   = p_shift - {1'b0, dvr_latch};
    // Sign bit: if 1, subtraction went negative → must restore partial
    wire                  p_neg   = p_sub[DIVISOR_BITS];

    // ── Sequential logic ───────────────────────────────────────────────────────
    always @(posedge clk) begin
        // Default deassert for one-cycle signals
        valid       <= 1'b0;
        div_by_zero <= 1'b0;

        if (!rst_n) begin
            state     <= S_IDLE;
            cnt       <= {CNT_W{1'b0}};
            dvd_shift <= {DIVIDEND_BITS{1'b0}};
            quot_acc  <= {DIVIDEND_BITS{1'b0}};
            dvr_latch <= {DIVISOR_BITS{1'b0}};
            partial   <= {(DIVISOR_BITS+1){1'b0}};
            quotient  <= {DIVIDEND_BITS{1'b0}};
        end else begin
            case (state)

                S_IDLE: begin
                    if (start) begin
                        if (divisor == {DIVISOR_BITS{1'b0}}) begin
                            // Division by zero: saturate output and flag
                            quotient    <= {DIVIDEND_BITS{1'b1}};
                            valid       <= 1'b1;
                            div_by_zero <= 1'b1;
                        end else begin
                            // Latch inputs and begin restoring division
                            dvd_shift <= dividend;
                            dvr_latch <= divisor;
                            partial   <= {(DIVISOR_BITS+1){1'b0}};
                            quot_acc  <= {DIVIDEND_BITS{1'b0}};
                            // cnt counts from DIVIDEND_BITS-1 down to 0
                            cnt       <= DIVIDEND_BITS - 1;
                            state     <= S_BUSY;
                        end
                    end
                end

                S_BUSY: begin
                    // Shift dividend register (exposes next bit next cycle via dvd_shift[MSB])
                    dvd_shift <= dvd_shift << 1;

                    if (cnt == {CNT_W{1'b0}}) begin
                        // ── Last step: output quotient directly ────────────────
                        // quot_acc holds bits [DIVIDEND_BITS-1:1] from prior steps;
                        // this cycle contributes the final LSB (~p_neg).
                        quotient <= {quot_acc[DIVIDEND_BITS-2:0], ~p_neg};
                        valid    <= 1'b1;
                        state    <= S_IDLE;
                        // Note: partial/remainder not captured (not needed by callers)
                    end else begin
                        // ── Intermediate step ──────────────────────────────────
                        // Restore if negative, accept subtracted partial if non-negative
                        partial  <= p_neg ? p_shift : p_sub;
                        // Shift quotient accumulator; quotient bit = ~p_neg (1=fit, 0=restore)
                        quot_acc <= {quot_acc[DIVIDEND_BITS-2:0], ~p_neg};
                        cnt      <= cnt - 1;
                    end
                end

                default: state <= S_IDLE; // safety net, unreachable in normal operation
            endcase
        end
    end

endmodule
