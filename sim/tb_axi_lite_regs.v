`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_axi_lite_regs
// DUT       : axi_lite_regs
// Simulator : Icarus Verilog (iverilog)
// =============================================================================
module tb_axi_lite_regs;

    localparam CLK_PERIOD = 20;

    reg         clk, rst_n;
    reg  [31:0] awaddr;
    reg  [2:0]  awprot;
    reg         awvalid;
    wire        awready;

    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;

    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;

    reg  [31:0] araddr;
    reg  [2:0]  arprot;
    reg         arvalid;
    wire        arready;

    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    reg  [11:0] ch0_raw, ch1_raw, ch2_raw, ch3_raw, ch4_raw, ch5_raw;
    reg  [31:0] ch0_resist, ch1_resist, ch2_resist, ch3_resist, ch4_resist, ch5_resist;
    reg  [31:0] ch0_base, ch1_base, ch2_base, ch3_base, ch4_base, ch5_base;
    reg  [31:0] status_in;
    reg  [31:0] alarm_log_in;

    wire [11:0] code_fs;
    wire [31:0] roc_thresh;
    wire [31:0] xfault_thresh;
    wire [3:0]  alpha_shift;
    wire [15:0] latch_cycles;
    wire [5:0]  ch_mask;
    wire        ctrl_enable;
    wire        ctrl_reset_base;
    wire        ctrl_alarm_ack;

    axi_lite_regs dut (
        .s_axi_aclk    (clk),
        .s_axi_aresetn (rst_n),
        .s_axi_awaddr  (awaddr),
        .s_axi_awprot  (awprot),
        .s_axi_awvalid (awvalid),
        .s_axi_awready (awready),
        .s_axi_wdata   (wdata),
        .s_axi_wstrb   (wstrb),
        .s_axi_wvalid  (wvalid),
        .s_axi_wready  (wready),
        .s_axi_bresp   (bresp),
        .s_axi_bvalid  (bvalid),
        .s_axi_bready  (bready),
        .s_axi_araddr  (araddr),
        .s_axi_arprot  (arprot),
        .s_axi_arvalid (arvalid),
        .s_axi_arready (arready),
        .s_axi_rdata   (rdata),
        .s_axi_rresp   (rresp),
        .s_axi_rvalid  (rvalid),
        .s_axi_rready  (rready),
        .ch0_raw(ch0_raw), .ch1_raw(ch1_raw), .ch2_raw(ch2_raw),
        .ch3_raw(ch3_raw), .ch4_raw(ch4_raw), .ch5_raw(ch5_raw),
        .ch0_resist(ch0_resist), .ch1_resist(ch1_resist), .ch2_resist(ch2_resist),
        .ch3_resist(ch3_resist), .ch4_resist(ch4_resist), .ch5_resist(ch5_resist),
        .ch0_base(ch0_base), .ch1_base(ch1_base), .ch2_base(ch2_base),
        .ch3_base(ch3_base), .ch4_base(ch4_base), .ch5_base(ch5_base),
        .status_in     (status_in),
        .alarm_log_in  (alarm_log_in),
        .code_fs       (code_fs),
        .roc_thresh    (roc_thresh),
        .xfault_thresh (xfault_thresh),
        .alpha_shift   (alpha_shift),
        .latch_cycles  (latch_cycles),
        .ch_mask       (ch_mask),
        .ctrl_enable   (ctrl_enable),
        .ctrl_reset_base(ctrl_reset_base),
        .ctrl_alarm_ack(ctrl_alarm_ack)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr  <= addr;
            awvalid <= 1'b1;
            wdata   <= data;
            wstrb   <= 4'hF;
            wvalid  <= 1'b1;
            bready  <= 1'b1;

            @(posedge clk);
            while (!awready || !wready) @(posedge clk);
            awvalid <= 1'b0;
            wvalid  <= 1'b0;

            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready <= 1'b0;
        end
    endtask

    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr  <= addr;
            arvalid <= 1'b1;
            rready  <= 1'b1;

            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid <= 1'b0;

            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
            rready <= 1'b0;
        end
    endtask

    reg [31:0] rdata_tmp;

    initial begin
        $dumpfile("tb_axi_lite_regs.vcd");
        $dumpvars(0, tb_axi_lite_regs);

        rst_n   = 0;
        awaddr  = 0; awprot = 0; awvalid = 0;
        wdata   = 0; wstrb  = 0; wvalid  = 0;
        bready  = 0;
        araddr  = 0; arprot = 0; arvalid = 0;
        rready  = 0;
        status_in    = 32'h0;
        alarm_log_in = 32'h0;
        ch0_raw = 0; ch1_raw = 0; ch2_raw = 0; ch3_raw = 0; ch4_raw = 0; ch5_raw = 0;
        ch0_resist = 0; ch1_resist = 0; ch2_resist = 0; ch3_resist = 0; ch4_resist = 0; ch5_resist = 0;
        ch0_base = 0; ch1_base = 0; ch2_base = 0; ch3_base = 0; ch4_base = 0; ch5_base = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== axi_lite_regs testbench ===");

        // Test 1: Reset defaults
        if (roc_thresh !== 32'd1000 || xfault_thresh !== 32'd5000 || code_fs !== 12'hFFF) begin
            $error("TEST 1 FAIL: reset defaults");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 1 PASS: default register values verified");
            pass_cnt = pass_cnt + 1;
        end

        // Test 2: Write ROC_THRESH (0x058)
        axi_write(32'h058, 32'h12345678);
        #1;
        if (roc_thresh !== 32'h12345678) begin
            $error("TEST 2 FAIL: write ROC_THRESH, got %h (exp 12345678)", roc_thresh);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2 PASS: write ROC_THRESH successful");
            pass_cnt = pass_cnt + 1;
        end

        // Test 3: Write CTRL (0x050) with enable=1, reset_base=1, alarm_ack=1
        // Data = 0x0000_0007 (bits [0]=1, [1]=1, [2]=1)
        axi_write(32'h050, 32'h0000_0007);
        #1;
        if (ctrl_enable !== 1'b1) begin
            $error("TEST 3 FAIL: CTRL enable bit not set");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3 PASS: CTRL write enable set successfully");
            pass_cnt = pass_cnt + 1;
        end

        // Check self-clearing (reset_base and alarm_ack should be 0 after write completes)
        if (ctrl_reset_base !== 1'b0 || ctrl_alarm_ack !== 1'b0) begin
            $error("TEST 3b FAIL: self-clearing control bits did not clear");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3b PASS: self-clearing control pulses cleared automatically after 1 cycle");
            pass_cnt = pass_cnt + 1;
        end

        // Test 4: Read CH0_RESIST (0x018)
        ch0_resist = 32'h000186A0; // 100,000 Ω
        axi_read(32'h018, rdata_tmp);
        #1;
        if (rdata_tmp !== 32'h000186A0) begin
            $error("TEST 4 FAIL: read CH0_RESIST, got %h (exp 000186A0)", rdata_tmp);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 4 PASS: read CH0_RESIST returned 100,000 Ω correctly");
            pass_cnt = pass_cnt + 1;
        end

        $display("");
        $display("====================================");
        $display("  PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  ALL TESTS PASSED");
        else               $display("  *** FAILURES DETECTED ***");
        $display("====================================");
        $finish;
    end

endmodule
