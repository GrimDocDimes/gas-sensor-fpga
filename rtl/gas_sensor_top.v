`timescale 1ns/1ps
// =============================================================================
// Module  : gas_sensor_top
// Purpose : Top-level integration for the FPGA-Based Multi-Channel Resistive
//           Gas Sensor Acquisition System on PYNQ-Z2 (xc7z020clg400-1).
//
// Hierarchy:
//   gas_sensor_top
//   ├── xadc_sequencer          (DRP read FSM)
//   ├── resistance_calc × 6     (voltage-divider formula, fixed-point)
//   ├── baseline_tracker × 6   (EMA baseline)
//   ├── roc_detector × 6       (|ΔR| rate-of-change alarm)
//   ├── cross_channel_fault     (mean deviation, exact ÷6)
//   ├── alarm_controller        (Moore FSM, latching, priority)
//   └── axi_lite_regs           (AXI4-Lite slave)
//
// Signal flow:
//   XADC → xadc_sequencer → (demux by ch) → resistance_calc[ch]
//       → baseline_tracker[ch] + roc_detector[ch]
//       → cross_channel_fault (trigger after all 6 updated)
//       → alarm_controller
//       → axi_lite_regs (status/data registers)
//       ← axi_lite_regs (config thresholds)
//
// Cross-channel trigger:
//   A 6-bit 'ch_updated' register is set when each channel gets a new
//   resistance result.  When all 6 bits are set (or all active-masked bits),
//   the cross_channel_fault module is triggered and ch_updated is cleared.
//
// XADC Wizard connection:
//   In the Vivado block design, xadc_wiz_0 drives the DRP signals connected
//   to xadc_sequencer.  The vauxp/vauxn ports of this module connect to the
//   xadc_wiz_0 VAUX ports in the block design.  (They are NOT DRP signals —
//   they are the raw analog input pins routed from the PYNQ-Z2 Arduino header.)
//
// Alarm output:
//   alarm_out drives on-board LED LD0 (see constraints/pynqz2_gas_sensor.xdc).
//
// AXI-Lite:
//   Connected to the PS via AXI Interconnect in the block design.
//   Base address 0x43C0_0000 (set in Address Editor).
// =============================================================================
module gas_sensor_top #(
    parameter NUM_CH    = 6,
    parameter CODE_W    = 12,
    parameter DATA_W    = 32,
    parameter R_KNOWN   = 10_000   // reference resistor Ω
) (
    // System clock and reset (from PS via Processor System Reset IP)
    input  wire         clk,
    input  wire         rst_n,      // sync active-low

    // ── XADC DRP interface (connect to xadc_wiz_0 in block design) ─────────────
    output wire         xadc_dclk,
    output wire         xadc_den,
    output wire         xadc_dwe,
    output wire [6:0]   xadc_daddr,
    output wire [15:0]  xadc_di,
    input  wire [15:0]  xadc_do,
    input  wire         xadc_drdy,
    input  wire         xadc_eos,
    input  wire [4:0]   xadc_channel,

    // ── Alarm outputs ────────────────────────────────────────────────────────────
    output wire         alarm_out,      // global alarm (drives LED LD0)
    output wire [5:0]   fault_out,      // per-channel fault flags

    // ── AXI4-Lite Slave Interface ────────────────────────────────────────────────
    input  wire         s_axi_aclk,
    input  wire         s_axi_aresetn,
    // Write address
    input  wire [31:0]  s_axi_awaddr,
    input  wire [2:0]   s_axi_awprot,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    // Write data
    input  wire [31:0]  s_axi_wdata,
    input  wire [3:0]   s_axi_wstrb,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    // Write response
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    // Read address
    input  wire [31:0]  s_axi_araddr,
    input  wire [2:0]   s_axi_arprot,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    // Read data
    output wire [31:0]  s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready
);

    // ── AXI-Lite config registers (from axi_lite_regs to processing chain) ──────
    wire [11:0]  cfg_code_fs;
    wire [31:0]  cfg_roc_thresh;
    wire [31:0]  cfg_xfault_thresh;
    wire [3:0]   cfg_alpha_shift;
    wire [15:0]  cfg_latch_cycles;
    wire [5:0]   cfg_ch_mask;
    wire         cfg_enable;
    wire         cfg_reset_base;
    wire         cfg_alarm_ack;

    // ── XADC sequencer outputs ──────────────────────────────────────────────────
    wire [CODE_W-1:0]  adc_data;
    wire [2:0]         adc_ch;
    wire               adc_valid;

    // ── Per-channel resistance outputs ─────────────────────────────────────────
    wire [DATA_W-1:0]  resist    [0:NUM_CH-1];
    wire               resist_vld[0:NUM_CH-1];
    // Raw XADC code per channel (latched when adc_valid)
    reg  [CODE_W-1:0]  raw_code  [0:NUM_CH-1];
    // OC/SC flags per channel
    wire               oc_flag   [0:NUM_CH-1];
    wire               sc_flag   [0:NUM_CH-1];

    // ── Per-channel baseline outputs ────────────────────────────────────────────
    wire [DATA_W-1:0]  baseline  [0:NUM_CH-1];
    wire               base_vld  [0:NUM_CH-1];

    // ── Per-channel RoC alarm outputs ──────────────────────────────────────────
    wire [DATA_W-1:0]  delta_r   [0:NUM_CH-1];
    wire               roc_alarm [0:NUM_CH-1];
    wire [5:0]         roc_alarms;
    assign roc_alarms = {roc_alarm[5], roc_alarm[4], roc_alarm[3],
                         roc_alarm[2], roc_alarm[1], roc_alarm[0]};

    // ── Cross-channel fault ─────────────────────────────────────────────────────
    wire [5:0]         xfaults;
    wire [DATA_W-1:0]  mean_resist;
    wire               xfault_vld;

    // ── Cross-channel trigger: assert when all active channels have new data ────
    reg  [5:0]  ch_updated;        // bit i set when channel i has a new result
    wire        all_updated = (ch_updated & cfg_ch_mask) == cfg_ch_mask;
    reg         xf_trigger;

    // ── STATUS register assembly ────────────────────────────────────────────────
    wire alarm_active, alarm_latched;
    wire [31:0] status_reg = {12'h0,
                              alarm_latched, alarm_active,
                              xfaults,
                              roc_alarms,
                              ch_updated};  // [5:0]=new_data

    // ── ALARM_LOG: sticky register updated by alarm_controller ─────────────────
    // (For simplicity, alarm_log mirrors fault_out — extend later if needed)
    wire [31:0] alarm_log  = {26'h0, fault_out};

    // ══════════════════════════════════════════════════════════════════════════════
    // Submodule instantiations
    // ══════════════════════════════════════════════════════════════════════════════

    // ── XADC DRP sequencer ──────────────────────────────────────────────────────
    xadc_sequencer #(
        .NUM_CH  (NUM_CH),
        .CODE_W  (CODE_W)
    ) u_xadc_seq (
        .clk       (clk),
        .rst_n     (rst_n),
        .dclk_out  (xadc_dclk),
        .den_out   (xadc_den),
        .dwe_out   (xadc_dwe),
        .daddr_out (xadc_daddr),
        .di_out    (xadc_di),
        .do_in     (xadc_do),
        .drdy_in   (xadc_drdy),
        .eos_in    (xadc_eos),
        .channel_in(xadc_channel),
        .adc_data  (adc_data),
        .adc_ch    (adc_ch),
        .adc_valid (adc_valid)
    );

    // ── Per-channel raw code latch & processing chain ──────────────────────────
    genvar g;
    generate
        for (g = 0; g < NUM_CH; g = g + 1) begin : gen_ch

            // Latch raw XADC code for AXI readback
            always @(posedge clk) begin
                if (!rst_n)
                    raw_code[g] <= {CODE_W{1'b0}};
                else if (adc_valid && (adc_ch == g))
                    raw_code[g] <= adc_data;
            end

            // Resistance calculator
            resistance_calc #(
                .R_KNOWN      (R_KNOWN),
                .CODE_WIDTH   (CODE_W),
                .RESULT_WIDTH (DATA_W)
            ) u_rcalc (
                .clk        (clk),
                .rst_n      (rst_n),
                .code_fs    (cfg_code_fs),
                .code_in    (adc_data),
                .valid_in   (adc_valid && (adc_ch == g[2:0])),
                .resist_out (resist[g]),
                .valid_out  (resist_vld[g]),
                .oc_flag    (oc_flag[g]),
                .sc_flag    (sc_flag[g])
            );

            // EMA baseline tracker
            baseline_tracker #(
                .DATA_WIDTH (DATA_W)
            ) u_base (
                .clk          (clk),
                .rst_n        (rst_n),
                .resist_in    (resist[g]),
                .valid_in     (resist_vld[g]),
                .alpha_shift  (cfg_alpha_shift),
                .reset_base   (cfg_reset_base),
                .baseline_out (baseline[g]),
                .baseline_vld (base_vld[g])
            );

            // Rate-of-change detector
            roc_detector #(
                .DATA_WIDTH (DATA_W)
            ) u_roc (
                .clk        (clk),
                .rst_n      (rst_n),
                .resist_in  (resist[g]),
                .valid_in   (resist_vld[g]),
                .roc_thresh (cfg_roc_thresh),
                .delta_r    (delta_r[g]),
                .roc_alarm  (roc_alarm[g])
            );

        end
    endgenerate

    // ── ch_updated tracker ─────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (!rst_n) begin
            ch_updated <= 6'b0;
            xf_trigger <= 1'b0;
        end else begin
            xf_trigger <= 1'b0;
            // Set bit when each channel gets a new result
            if (resist_vld[0]) ch_updated[0] <= 1'b1;
            if (resist_vld[1]) ch_updated[1] <= 1'b1;
            if (resist_vld[2]) ch_updated[2] <= 1'b1;
            if (resist_vld[3]) ch_updated[3] <= 1'b1;
            if (resist_vld[4]) ch_updated[4] <= 1'b1;
            if (resist_vld[5]) ch_updated[5] <= 1'b1;
            // When all active channels updated, trigger cross-channel check
            if (all_updated && cfg_enable) begin
                xf_trigger <= 1'b1;
                ch_updated <= 6'b0;  // clear for next round
            end
        end
    end

    // ── Cross-channel fault detector ───────────────────────────────────────────
    cross_channel_fault #(
        .NUM_CH     (NUM_CH),
        .DATA_WIDTH (DATA_W)
    ) u_xfault (
        .clk        (clk),
        .rst_n      (rst_n),
        .resist0    (resist[0]),
        .resist1    (resist[1]),
        .resist2    (resist[2]),
        .resist3    (resist[3]),
        .resist4    (resist[4]),
        .resist5    (resist[5]),
        .trigger    (xf_trigger),
        .ch_mask    (cfg_ch_mask),
        .xf_thresh  (cfg_xfault_thresh),
        .fault_out  (xfaults),
        .mean_out   (mean_resist),
        .fault_vld  (xfault_vld)
    );

    // ── Alarm controller ────────────────────────────────────────────────────────
    alarm_controller #(
        .NUM_CH  (NUM_CH),
        .LATCH_W (16)
    ) u_alarm (
        .clk          (clk),
        .rst_n        (rst_n),
        .roc_alarms   (roc_alarms),
        .xfaults      (xfaults),
        .alarm_ack    (cfg_alarm_ack),
        .latch_cycles (cfg_latch_cycles),
        .alarm_out    (alarm_out),
        .fault_out    (fault_out),
        .alarm_active (alarm_active),
        .alarm_latched(alarm_latched)
    );

    // ── AXI-Lite register file ──────────────────────────────────────────────────
    axi_lite_regs #(
        .C_S_AXI_DATA_WIDTH (32),
        .C_S_AXI_ADDR_WIDTH (32)
    ) u_axi (
        .s_axi_aclk     (s_axi_aclk),
        .s_axi_aresetn  (s_axi_aresetn),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        // PL→register inputs
        .ch0_raw        (raw_code[0]), .ch1_raw(raw_code[1]), .ch2_raw(raw_code[2]),
        .ch3_raw        (raw_code[3]), .ch4_raw(raw_code[4]), .ch5_raw(raw_code[5]),
        .ch0_resist     (resist[0]),   .ch1_resist(resist[1]), .ch2_resist(resist[2]),
        .ch3_resist     (resist[3]),   .ch4_resist(resist[4]), .ch5_resist(resist[5]),
        .ch0_base       (baseline[0]), .ch1_base(baseline[1]), .ch2_base(baseline[2]),
        .ch3_base       (baseline[3]), .ch4_base(baseline[4]), .ch5_base(baseline[5]),
        .status_in      (status_reg),
        .alarm_log_in   (alarm_log),
        // Register→PL outputs
        .code_fs        (cfg_code_fs),
        .roc_thresh     (cfg_roc_thresh),
        .xfault_thresh  (cfg_xfault_thresh),
        .alpha_shift    (cfg_alpha_shift),
        .latch_cycles   (cfg_latch_cycles),
        .ch_mask        (cfg_ch_mask),
        .ctrl_enable    (cfg_enable),
        .ctrl_reset_base(cfg_reset_base),
        .ctrl_alarm_ack (cfg_alarm_ack)
    );

endmodule
