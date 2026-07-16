// =============================================================================
// Gas Sensing System — Top-Level Module
// Board:  Nexys 4 DDR / Nexys A7-100T (Artix-7 XC7A100T)
// Target: Vivado 2023.x, LVCMOS33
//
// Instantiates:
//   - XADC gas wrapper (auxiliary channel 6, 0–1V unipolar)
//   - Debouncer for baseline-capture button (BTNC)
//   - Baseline + delta + sensitivity logic
//   - Warm-up timer
//   - 8-digit 7-segment display driver
//   - UART TX + ASCII frame builder
// =============================================================================

`timescale 1ns / 1ps

module top (
    // System
    input  wire        CLK100MHZ,
    input  wire        CPU_RESETN,     // Active-low reset

    // JXADC analog input — differential pair for auxiliary channel 6
    // Connect: VAUXP6 → V_out2 (scaled 0–1V), VAUXN6 → GND
    input  wire        VAUXP6,
    input  wire        VAUXN6,

    // UART (USB-CDC via FT2232H — same cable as JTAG)
    output wire        UART_RXD_OUT,   // FPGA→PC TX

    // 7-Segment Display (8-digit, shared-anode, active-low)
    output wire [7:0]  AN,
    output wire        CA, CB, CC, CD, CE, CF, CG, DP,

    // LEDs
    output wire [15:0] LED,
    output wire        LED16_R,        // Warm-up in progress (red)
    output wire        LED16_G,        // Warm-up done / ready (green)
    output wire        LED16_B,
    output wire        LED17_R,
    output wire        LED17_G,
    output wire        LED17_B,

    // Buttons & Switches
    input  wire        BTNC,           // Baseline capture
    input  wire [0:0]  SW              // SW[0]: display mode (0=sensitivity, 1=delta)
);

    // =========================================================================
    // Reset (active-high, synchronous)
    // =========================================================================
    wire rst = ~CPU_RESETN;

    // =========================================================================
    // Internal signals
    // =========================================================================
    wire [11:0] adc_code;
    wire        adc_valid;

    wire        btn_debounced;
    wire        btn_capture;      // Single-cycle rising-edge pulse

    wire [11:0] r_air;
    wire [11:0] r_gas;
    wire [12:0] delta;
    wire [15:0] sensitivity;
    wire        baseline_valid;
    wire        result_valid;

    wire        warmup_done;

    wire [7:0]  uart_byte;
    wire        uart_valid;
    wire        uart_ready;

    wire [6:0]  seg_bus;

    // =========================================================================
    // XADC — Auxiliary Channel 6
    // =========================================================================
    xadc_gas_wrapper u_xadc (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .vauxp6     (VAUXP6),
        .vauxn6     (VAUXN6),
        .adc_code   (adc_code),
        .data_valid (adc_valid)
    );

    // =========================================================================
    // Button Debouncer — BTNC
    // =========================================================================
    debounce #(
        .CLK_FREQ    (100_000_000),
        .DEBOUNCE_MS (20)
    ) u_deb (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .btn_in     (BTNC),
        .btn_out    (btn_debounced),
        .btn_rising (btn_capture)
    );

    // =========================================================================
    // Baseline Capture & Delta / Sensitivity
    // =========================================================================
    baseline_delta #(
        .USE_DIVIDER_IP (0)    // Set to 1 if you add Vivado Divider IP
    ) u_delta (
        .clk            (CLK100MHZ),
        .rst            (rst),
        .adc_code       (adc_code),
        .adc_valid      (adc_valid),
        .btn_capture    (btn_capture),
        .r_air          (r_air),
        .r_gas          (r_gas),
        .delta          (delta),
        .sensitivity    (sensitivity),
        .baseline_valid (baseline_valid),
        .result_valid   (result_valid)
    );

    // =========================================================================
    // Warm-Up Timer (3 minutes)
    // Change WARMUP_SECONDS to 10 for quick bring-up testing
    // =========================================================================
    warmup_timer #(
        .CLK_FREQ       (100_000_000),
        .WARMUP_SECONDS (180)
    ) u_warmup (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .warmup_done(warmup_done),
        .led_red    (LED16_R),
        .led_green  (LED16_G)
    );

    // =========================================================================
    // 7-Segment Display
    // =========================================================================
    seg7_display u_seg7 (
        .clk            (CLK100MHZ),
        .rst            (rst),
        .delta          (delta),
        .sensitivity    (sensitivity),
        .baseline_valid (baseline_valid),
        .mode           (SW[0]),
        .an             (AN),
        .seg            (seg_bus),
        .dp             (DP)
    );

    assign {CA, CB, CC, CD, CE, CF, CG} = seg_bus;

    // =========================================================================
    // UART Frame Builder → UART TX
    // =========================================================================
    uart_framer #(
        .CLK_FREQ        (100_000_000),
        .INTERVAL_CYCLES (10_000_000)   // One frame every 100 ms
    ) u_framer (
        .clk            (CLK100MHZ),
        .rst            (rst),
        .r_gas          (r_gas),
        .r_air          (r_air),
        .delta          (delta),
        .sensitivity    (sensitivity),
        .baseline_valid (baseline_valid),
        .uart_data      (uart_byte),
        .uart_valid     (uart_valid),
        .uart_ready     (uart_ready)
    );

    uart_tx #(
        .CLK_FREQ (100_000_000),
        .BAUD     (115_200)
    ) u_uart (
        .clk        (CLK100MHZ),
        .rst        (rst),
        .data_in    (uart_byte),
        .data_valid (uart_valid),
        .tx_ready   (uart_ready),
        .tx         (UART_RXD_OUT)
    );

    // =========================================================================
    // LED Bar Graph — raw ADC code on LED[11:0], status on 13–15
    // =========================================================================
    assign LED[11:0] = adc_code;
    assign LED[12]   = baseline_valid;
    assign LED[13]   = warmup_done;
    assign LED[15:14]= 2'b00;

    // Unused RGB LEDs
    assign LED16_B   = 1'b0;
    assign LED17_R   = 1'b0;
    assign LED17_G   = 1'b0;
    assign LED17_B   = 1'b0;

endmodule
