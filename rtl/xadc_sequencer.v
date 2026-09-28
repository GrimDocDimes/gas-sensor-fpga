`timescale 1ns/1ps
// =============================================================================
// Module  : xadc_sequencer
// Purpose : XADC Wizard IP wrapper + DRP read FSM for 6-channel gas sensor array.
//
// In the Vivado block design, this module connects to the xadc_wiz_0 IP
// instantiated separately.  Here we implement the DRP (Dynamic Reconfiguration
// Port) read state machine that captures each channel's conversion result and
// outputs it with a channel-ID tag and a valid pulse.
//
// XADC Wizard IP configuration (set in Vivado IP Customisation wizard):
//   - Interface     : DRP
//   - Sequencer     : Continuous automatic sequencer
//   - Channels      : VAUX1, VAUX9, VAUX6, VAUX15, VAUX5, VAUX13
//                     (Arduino A0–A5 on PYNQ-Z2)
//   - Mode          : Unipolar single-ended
//   - DCLK          : 50 MHz (tied to clk_pl)
//   - ADCCLK        : DCLK/4 = 12.5 MHz (automatic inside Wizard)
//   - Output        : 16-bit left-justified (bits [15:4] = 12-bit result)
//
// XADC DRP address map for auxiliary channels (from Xilinx UG480):
//   VAUX1  → DRP address 0x11
//   VAUX9  → DRP address 0x19
//   VAUX6  → DRP address 0x16
//   VAUX15 → DRP address 0x1F
//   VAUX5  → DRP address 0x15
//   VAUX13 → DRP address 0x1D
//
// DRP Read FSM:
//   WAIT_EOC  — wait for end-of-conversion pulse from XADC (eos_out from Wizard)
//   SEND_ADDR — assert den_in, drive drp_addr to read the completed channel
//   WAIT_DRDY — wait for drdy_out from XADC (data ready)
//   CAPTURE   — latch do_out[15:4] as 12-bit result and tag with channel index
//
// The XADC Wizard's automatic sequencer cycles through channels and asserts
// 'eos_out' (end-of-sequence) after all channels have been converted.
// Each eos_out pulse triggers a DRP read of all 6 channels in sequence.
//
// For simulation:
//   The xadc_wiz port signals are exposed so the testbench can substitute a
//   behavioural XADC model (xadc_wiz_model.v) in place of the Xilinx IP.
//
// Synthesis note:
//   In the Vivado block design, xadc_wiz_0 is instantiated alongside this
//   module and wired to the xadc_wiz_* ports below.
//   Do NOT instantiate xadc_wiz inside this RTL file — keep the IP in the
//   block design for correct Vivado flow.
// =============================================================================
module xadc_sequencer #(
    parameter NUM_CH    = 6,
    parameter CODE_W    = 12    // XADC output resolution
) (
    input  wire              clk,
    input  wire              rst_n,       // sync active-low reset

    // ── XADC Wizard DRP ports (connect to xadc_wiz_0 in block design) ─────────
    // DRP clock (= clk)
    output wire              dclk_out,
    // DRP enable (read strobe)
    output reg               den_out,
    // DRP write enable (always 0: read only)
    output wire              dwe_out,
    // DRP address (7-bit channel address)
    output reg  [6:0]        daddr_out,
    // DRP data in (unused for reads — tie to 0)
    output wire [15:0]       di_out,
    // DRP data out (16-bit: bits[15:4] = 12-bit ADC result, left-justified)
    input  wire [15:0]       do_in,
    // DRP data ready
    input  wire              drdy_in,
    // End-of-sequence (XADC completed full channel sweep)
    input  wire              eos_in,
    // Channel-in-progress (4-bit current channel ID from XADC)
    input  wire [4:0]        channel_in,

    // ── Sampled output (one pulse per channel per conversion cycle) ────────────
    output reg  [CODE_W-1:0] adc_data,   // 12-bit ADC code
    output reg  [2:0]        adc_ch,     // channel index (0..5)
    output reg               adc_valid   // 1-cycle pulse: adc_data/adc_ch valid
);

    // ── DRP address table: maps channel index to DRP register address ──────────
    // Source: Xilinx UG480 Table 2-7 (Zynq-7000 XADC register map)
    // Arduino pin → VAUX channel → DRP address
    //   A0 → VAUX1  → 0x11
    //   A1 → VAUX9  → 0x19
    //   A2 → VAUX6  → 0x16
    //   A3 → VAUX15 → 0x1F
    //   A4 → VAUX5  → 0x15
    //   A5 → VAUX13 → 0x1D
    function [6:0] ch_to_drp_addr;
        input [2:0] ch;
        case (ch)
            3'd0: ch_to_drp_addr = 7'h11; // A0 → VAUX1
            3'd1: ch_to_drp_addr = 7'h19; // A1 → VAUX9
            3'd2: ch_to_drp_addr = 7'h16; // A2 → VAUX6
            3'd3: ch_to_drp_addr = 7'h1F; // A3 → VAUX15
            3'd4: ch_to_drp_addr = 7'h15; // A4 → VAUX5
            3'd5: ch_to_drp_addr = 7'h1D; // A5 → VAUX13
            default: ch_to_drp_addr = 7'h00;
        endcase
    endfunction

    // ── Tie-offs ───────────────────────────────────────────────────────────────
    assign dclk_out = clk;   // DRP clock = system clock
    assign dwe_out  = 1'b0;  // read-only DRP access
    assign di_out   = 16'h0; // unused (write data)

    // ── FSM ───────────────────────────────────────────────────────────────────
    localparam S_WAIT_EOS  = 2'd0;
    localparam S_SEND_ADDR = 2'd1;
    localparam S_WAIT_DRDY = 2'd2;
    localparam S_CAPTURE   = 2'd3;
    reg [1:0] state;

    reg [2:0] read_ch;   // which channel we are currently reading via DRP

    always @(posedge clk) begin
        // Default deassert one-cycle signals
        den_out   <= 1'b0;
        adc_valid <= 1'b0;

        if (!rst_n) begin
            state     <= S_WAIT_EOS;
            daddr_out <= 7'h00;
            adc_data  <= {CODE_W{1'b0}};
            adc_ch    <= 3'd0;
            read_ch   <= 3'd0;
        end else begin
            case (state)

                // ── Wait for XADC to complete a full sweep ─────────────────────
                S_WAIT_EOS: begin
                    read_ch <= 3'd0; // start reading from channel 0
                    if (eos_in) begin
                        state <= S_SEND_ADDR;
                    end
                end

                // ── Issue DRP read for current channel ─────────────────────────
                S_SEND_ADDR: begin
                    daddr_out <= ch_to_drp_addr(read_ch);
                    den_out   <= 1'b1;  // DRP enable (read strobe)
                    state     <= S_WAIT_DRDY;
                end

                // ── Wait for DRDY (data ready from XADC) ──────────────────────
                S_WAIT_DRDY: begin
                    den_out <= 1'b0;    // deassert immediately after 1 cycle
                    if (drdy_in) begin
                        state <= S_CAPTURE;
                    end
                end

                // ── Latch result and advance to next channel ───────────────────
                S_CAPTURE: begin
                    // do_in[15:4] = 12-bit ADC result (left-justified 16-bit word)
                    adc_data  <= do_in[15:4];
                    adc_ch    <= read_ch;
                    adc_valid <= 1'b1;

                    if (read_ch == NUM_CH - 1) begin
                        // All channels read for this sweep
                        read_ch <= 3'd0;
                        state   <= S_WAIT_EOS;
                    end else begin
                        // Read next channel
                        read_ch <= read_ch + 1;
                        state   <= S_SEND_ADDR;
                    end
                end

                default: state <= S_WAIT_EOS;
            endcase
        end
    end

endmodule
