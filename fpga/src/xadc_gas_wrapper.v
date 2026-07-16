// =============================================================================
// Gas Sensing System — XADC Gas Wrapper
// Board:  Nexys 4 DDR / Nexys A7-100T (Artix-7 XC7A100T)
// Target: Vivado 2023.x
//
// Reads auxiliary analog channel 6 (VAUXP[6]/VAUXN[6]) via the XADC primitive.
// The input must be a single-ended 0–1 V signal (unipolar).
//
// DRP address for AUX channel 6 result register: 7'h16
//
// Output:
//   adc_code  [11:0]  — 12-bit ADC result (MSBs of the 16-bit DRP word)
//   data_valid         — single-cycle pulse when adc_code is updated
// =============================================================================

`timescale 1ns / 1ps

module xadc_gas_wrapper (
    input  wire        clk,
    input  wire        rst,
    // Differential analog input pair from JXADC header
    input  wire        vauxp6,
    input  wire        vauxn6,
    // Outputs
    output reg  [11:0] adc_code,
    output reg         data_valid
);

    // -------------------------------------------------------------------------
    // Internal DRP / XADC signals
    // -------------------------------------------------------------------------
    wire [15:0] do_out;
    wire        drdy;
    wire [4:0]  channel;
    wire        eoc;
    wire        busy;

    // -------------------------------------------------------------------------
    // XADC Primitive
    //
    // Key register settings:
    //   INIT_40 = 9000h  Calibration: ADC + supply sensor calibration enable
    //   INIT_41 = 2000h  Continuous-mode sequencer
    //   INIT_42 = 0400h  Clock divider = 4 → ADCCLK = 100MHz/4 = 25MHz (max 26 MHz)
    //   INIT_48 = 0040h  Sequencer channel enable: AUX6 only (bit 6 = 1)
    //   INIT_49 = 0040h  Sequencer acquisition time: same mask
    //   All alarm thresholds left at reset defaults (unused here)
    // -------------------------------------------------------------------------
    XADC #(
        .INIT_40 (16'h9000),   // Calibration: ADC + sensor offset
        .INIT_41 (16'h2000),   // Continuous sequencer mode
        .INIT_42 (16'h0400),   // DCLK divider = 4 → 25 MHz ADCCLK
        .INIT_48 (16'h0040),   // Sequencer: enable AUX channel 6 only
        .INIT_49 (16'h0040),   // Acquisition time: 10-cycle settling for AUX6
        .INIT_4A (16'h0000),
        .INIT_4B (16'h0000),
        .INIT_4C (16'h0000),
        .INIT_4D (16'h0000),
        .INIT_4E (16'h0000),
        .INIT_4F (16'h0000),
        .INIT_50 (16'hB5ED),   // Over-temp threshold (default, unused)
        .INIT_51 (16'h57E4),
        .INIT_52 (16'hA147),
        .INIT_53 (16'hCA33),
        .INIT_54 (16'h4E10),
        .INIT_55 (16'h5999),
        .INIT_56 (16'h91EB),
        .INIT_57 (16'hAE4E),
        .INIT_58 (16'h5111),
        .INIT_5C (16'h5111),
        .SIM_DEVICE ("7SERIES")
    ) xadc_inst (
        // Conversion trigger — use EOC to trigger DRP read (continuous)
        .CONVST    (1'b0),
        .CONVSTCLK (1'b0),
        // DRP interface
        .DADDR     (7'h16),    // AUX channel 6 result register
        .DCLK      (clk),
        .DEN       (eoc),      // Read result when conversion is done
        .DI        (16'h0),
        .DWE       (1'b0),
        // Reset
        .RESET     (rst),
        // Analog inputs — only AUX6 connected; all others tied off
        .VAUXP     (16'b0000_0000_0100_0000),  // bit 6 = vauxp6
        .VAUXN     (16'b0000_0000_0100_0000),  // bit 6 = vauxn6
        // Outputs
        .DO        (do_out),
        .DRDY      (drdy),
        .EOC       (eoc),
        .EOS       (),
        .CHANNEL   (channel),
        .BUSY      (busy),
        .ALM       (),
        .OT        (),
        .MUXADDR   (),
        .JTAGBUSY  (),
        .JTAGLOCKED(),
        .JTAGMODIFIED(),
        // On-chip VP/VN — not used
        .VP        (1'b0),
        .VN        (1'b0)
    );

    // -------------------------------------------------------------------------
    // Capture result on DRDY when channel matches AUX6 (5'h16)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            adc_code   <= 12'h0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            if (drdy && channel == 5'h16) begin
                adc_code   <= do_out[15:4];   // 12 MSBs = ADC result
                data_valid <= 1'b1;
            end
        end
    end

endmodule
