`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_cross_channel_fault
// DUT       : cross_channel_fault
// Simulator : Icarus Verilog (iverilog)
// =============================================================================
module tb_cross_channel_fault;

    localparam CLK_PERIOD = 20;
    localparam NUM_CH     = 6;
    localparam DATA_WIDTH = 32;

    reg                   clk, rst_n;
    reg  [DATA_WIDTH-1:0] r0, r1, r2, r3, r4, r5;
    reg                   trigger;
    reg  [NUM_CH-1:0]     ch_mask;
    reg  [DATA_WIDTH-1:0] xf_thresh;
    wire [NUM_CH-1:0]     fault_out;
    wire [DATA_WIDTH-1:0] mean_out;
    wire                  fault_vld;

    cross_channel_fault #(
        .NUM_CH    (NUM_CH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .resist0  (r0),
        .resist1  (r1),
        .resist2  (r2),
        .resist3  (r3),
        .resist4  (r4),
        .resist5  (r5),
        .trigger  (trigger),
        .ch_mask  (ch_mask),
        .xf_thresh(xf_thresh),
        .fault_out(fault_out),
        .mean_out (mean_out),
        .fault_vld(fault_vld)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    initial begin
        $dumpfile("tb_cross_channel_fault.vcd");
        $dumpvars(0, tb_cross_channel_fault);

        rst_n     = 0;
        r0 = 0; r1 = 0; r2 = 0; r3 = 0; r4 = 0; r5 = 0;
        trigger   = 0;
        ch_mask   = 6'h3F;  // all 6 active
        xf_thresh = 2000;   // 2 kΩ thresh

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== cross_channel_fault testbench ===");

        // Test 1: Reset state
        if (fault_out !== 0 || fault_vld !== 0) begin
            $error("TEST 1 FAIL: reset state");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 1 PASS: reset state verified");
            pass_cnt = pass_cnt + 1;
        end

        // Test 2: Equal resistances across all 6 channels (10,000 Ω each)
        r0 = 10000; r1 = 10000; r2 = 10000;
        r3 = 10000; r4 = 10000; r5 = 10000;
        @(posedge clk);
        trigger <= 1'b1;
        @(posedge clk);
        trigger <= 1'b0;

        // Wait for computation to complete
        @(posedge fault_vld);
        #1;
        if (mean_out !== 32'd10000 || fault_out !== 6'b000000) begin
            $error("TEST 2 FAIL: equal channels mean=%0d (exp 10000) faults=%b (exp 000000)",
                   mean_out, fault_out);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2 PASS: equal channels mean 10000, 0 faults");
            pass_cnt = pass_cnt + 1;
        end

        // Test 3: CH2 deviating significantly (20,000 Ω vs 10,000 Ω)
        r0 = 10000; r1 = 10000; r2 = 20000;
        r3 = 10000; r4 = 10000; r5 = 10000;
        @(posedge clk);
        trigger <= 1'b1;
        @(posedge clk);
        trigger <= 1'b0;

        @(posedge fault_vld);
        #1;
        // Sum = 70000, mean = 70000/6 = 11666.
        // CH2 diff = 20000 - 11666 = 8334 > 2000 threshold.
        // CH0,1,3,4,5 diff = 1666 <= 2000 threshold.
        // Expected fault_out = 6'b000100 (bit 2 set)
        if (mean_out !== 32'd11666 || fault_out !== 6'b000100) begin
            $error("TEST 3 FAIL: CH2 deviating mean=%0d (exp 11666) faults=%b (exp 000100)",
                   mean_out, fault_out);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3 PASS: CH2 deviation accurately flagged (mean 11666, fault_out=000100)");
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
