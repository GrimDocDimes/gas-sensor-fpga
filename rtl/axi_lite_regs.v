`timescale 1ns/1ps
// =============================================================================
// Module  : axi_lite_regs
// Purpose : AXI4-Lite slave register file for gas sensor acquisition system.
// =============================================================================
module axi_lite_regs #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 32
) (
    // AXI-Lite clock and reset
    input  wire                               s_axi_aclk,
    input  wire                               s_axi_aresetn, // active-low

    // AXI-Lite Write Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                         s_axi_awprot,
    input  wire                               s_axi_awvalid,
    output reg                                s_axi_awready,

    // AXI-Lite Write Data Channel
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0]   s_axi_wstrb,
    input  wire                               s_axi_wvalid,
    output reg                                s_axi_wready,

    // AXI-Lite Write Response Channel
    output reg  [1:0]                         s_axi_bresp,
    output reg                                s_axi_bvalid,
    input  wire                               s_axi_bready,

    // AXI-Lite Read Address Channel
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                         s_axi_arprot,
    input  wire                               s_axi_arvalid,
    output reg                                s_axi_arready,

    // AXI-Lite Read Data Channel
    output reg  [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                         s_axi_rresp,
    output reg                                s_axi_rvalid,
    input  wire                               s_axi_rready,

    // ── PL → Register inputs (6 channels individual signals for V2001 compatibility) ──
    input  wire [11:0]   ch0_raw, ch1_raw, ch2_raw, ch3_raw, ch4_raw, ch5_raw,
    input  wire [31:0]   ch0_resist, ch1_resist, ch2_resist, ch3_resist, ch4_resist, ch5_resist,
    input  wire [31:0]   ch0_base, ch1_base, ch2_base, ch3_base, ch4_base, ch5_base,
    input  wire [31:0]   status_in,
    input  wire [31:0]   alarm_log_in,

    // ── Register → PL outputs (configuration) ──────────────────────────────────
    output reg  [11:0]   code_fs,
    output reg  [31:0]   roc_thresh,
    output reg  [31:0]   xfault_thresh,
    output reg  [3:0]    alpha_shift,
    output reg  [15:0]   latch_cycles,
    output reg  [5:0]    ch_mask,
    output reg           ctrl_enable,
    output reg           ctrl_reset_base,
    output reg           ctrl_alarm_ack
);

    // Address decoding (word-aligned: bits [8:2])
    localparam ADDR_CH0_RAW     = 7'h00;
    localparam ADDR_CH1_RAW     = 7'h01;
    localparam ADDR_CH2_RAW     = 7'h02;
    localparam ADDR_CH3_RAW     = 7'h03;
    localparam ADDR_CH4_RAW     = 7'h04;
    localparam ADDR_CH5_RAW     = 7'h05;
    localparam ADDR_CH0_RESIST  = 7'h06;
    localparam ADDR_CH1_RESIST  = 7'h07;
    localparam ADDR_CH2_RESIST  = 7'h08;
    localparam ADDR_CH3_RESIST  = 7'h09;
    localparam ADDR_CH4_RESIST  = 7'h0A;
    localparam ADDR_CH5_RESIST  = 7'h0B;
    localparam ADDR_CH0_BASE    = 7'h0C;
    localparam ADDR_CH1_BASE    = 7'h0D;
    localparam ADDR_CH2_BASE    = 7'h0E;
    localparam ADDR_CH3_BASE    = 7'h0F;
    localparam ADDR_CH4_BASE    = 7'h10;
    localparam ADDR_CH5_BASE    = 7'h11;
    localparam ADDR_STATUS      = 7'h12;
    localparam ADDR_ALARM_LOG   = 7'h13;
    localparam ADDR_CTRL        = 7'h14;
    localparam ADDR_CODE_FS     = 7'h15;
    localparam ADDR_ROC_THRESH  = 7'h16;
    localparam ADDR_XFLT_THRESH = 7'h17;
    localparam ADDR_ALPHA_SHIFT = 7'h18;
    localparam ADDR_LATCH_CYC   = 7'h19;

    reg [6:0] aw_addr_latch;
    reg [6:0] ar_addr_latch;

    reg aw_done, w_done;
    reg [31:0] w_data_latch;
    reg [3:0]  w_strb_latch;

    // ── Write path ─────────────────────────────────────────────────────────────
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            aw_addr_latch  <= 7'h0;
            w_data_latch   <= 32'h0;
            w_strb_latch   <= 4'h0;
            code_fs        <= 12'hFFF;
            roc_thresh     <= 32'd1000;
            xfault_thresh  <= 32'd5000;
            alpha_shift    <= 4'd4;
            latch_cycles   <= 16'd10;
            ch_mask        <= 6'b111111;
            ctrl_enable    <= 1'b0;
            ctrl_reset_base<= 1'b0;
            ctrl_alarm_ack <= 1'b0;
        end else begin
            ctrl_reset_base <= 1'b0;
            ctrl_alarm_ack  <= 1'b0;

            if (s_axi_awvalid && !aw_done) begin
                s_axi_awready <= 1'b1;
                aw_addr_latch <= s_axi_awaddr[8:2];
                aw_done       <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
            end

            if (s_axi_wvalid && !w_done) begin
                s_axi_wready <= 1'b1;
                w_data_latch <= s_axi_wdata;
                w_strb_latch <= s_axi_wstrb;
                w_done       <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end

            if (aw_done && w_done && !s_axi_bvalid) begin
                case (aw_addr_latch)
                    ADDR_CTRL: begin
                        ctrl_enable     <= w_data_latch[0];
                        ctrl_reset_base <= w_data_latch[1];
                        ctrl_alarm_ack  <= w_data_latch[2];
                        ch_mask         <= w_data_latch[9:4];
                    end
                    ADDR_CODE_FS:     code_fs        <= w_data_latch[11:0];
                    ADDR_ROC_THRESH:  roc_thresh     <= w_data_latch;
                    ADDR_XFLT_THRESH: xfault_thresh  <= w_data_latch;
                    ADDR_ALPHA_SHIFT: alpha_shift     <= w_data_latch[3:0];
                    ADDR_LATCH_CYC:   latch_cycles    <= w_data_latch[15:0];
                    default: ;
                endcase

                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                aw_done      <= 1'b0;
                w_done       <= 1'b0;
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // ── Read path ──────────────────────────────────────────────────────────────
    always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
            ar_addr_latch <= 7'h0;
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                ar_addr_latch <= s_axi_araddr[8:2];

                case (s_axi_araddr[8:2])
                    ADDR_CH0_RAW:    s_axi_rdata <= {20'h0, ch0_raw};
                    ADDR_CH1_RAW:    s_axi_rdata <= {20'h0, ch1_raw};
                    ADDR_CH2_RAW:    s_axi_rdata <= {20'h0, ch2_raw};
                    ADDR_CH3_RAW:    s_axi_rdata <= {20'h0, ch3_raw};
                    ADDR_CH4_RAW:    s_axi_rdata <= {20'h0, ch4_raw};
                    ADDR_CH5_RAW:    s_axi_rdata <= {20'h0, ch5_raw};
                    ADDR_CH0_RESIST: s_axi_rdata <= ch0_resist;
                    ADDR_CH1_RESIST: s_axi_rdata <= ch1_resist;
                    ADDR_CH2_RESIST: s_axi_rdata <= ch2_resist;
                    ADDR_CH3_RESIST: s_axi_rdata <= ch3_resist;
                    ADDR_CH4_RESIST: s_axi_rdata <= ch4_resist;
                    ADDR_CH5_RESIST: s_axi_rdata <= ch5_resist;
                    ADDR_CH0_BASE:   s_axi_rdata <= ch0_base;
                    ADDR_CH1_BASE:   s_axi_rdata <= ch1_base;
                    ADDR_CH2_BASE:   s_axi_rdata <= ch2_base;
                    ADDR_CH3_BASE:   s_axi_rdata <= ch3_base;
                    ADDR_CH4_BASE:   s_axi_rdata <= ch4_base;
                    ADDR_CH5_BASE:   s_axi_rdata <= ch5_base;
                    ADDR_STATUS:     s_axi_rdata <= status_in;
                    ADDR_ALARM_LOG:  s_axi_rdata <= alarm_log_in;
                    ADDR_CTRL:       s_axi_rdata <= {22'h0, ch_mask, 2'b00, ctrl_enable};
                    ADDR_CODE_FS:    s_axi_rdata <= {20'h0, code_fs};
                    ADDR_ROC_THRESH: s_axi_rdata <= roc_thresh;
                    ADDR_XFLT_THRESH:s_axi_rdata <= xfault_thresh;
                    ADDR_ALPHA_SHIFT:s_axi_rdata <= {28'h0, alpha_shift};
                    ADDR_LATCH_CYC:  s_axi_rdata <= {16'h0, latch_cycles};
                    default:         s_axi_rdata <= 32'hDEAD_BEEF;
                endcase

                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
            end else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
