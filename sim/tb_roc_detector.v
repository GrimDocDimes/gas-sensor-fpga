`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_roc_detector
// DUT       : roc_detector
// Simulator : Icarus Verilog (iverilog)
// =============================================================================
module tb_roc_detector;

    localparam CLK_PERIOD = 20;
    localparam DATA_WIDTH = 32;

    reg                   clk, rst_n;
    reg  [DATA_WIDTH-1:0] resist_in;
    reg                   valid_in;
    reg  [DATA_WIDTH-1:0] roc_thresh;
    wire [DATA_WIDTH-1:0] delta_r;
    wire                  roc_alarm;

    roc_detector #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .resist_in (resist_in),
        .valid_in  (valid_in),
        .roc_thresh(roc_thresh),
        .delta_r   (delta_r),
        .roc_alarm (roc_alarm)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    task send_sample;
        input [31:0] r;
        begin
            @(posedge clk);
            resist_in <= r;
            valid_in  <= 1'b1;
            @(posedge clk);
            valid_in  <= 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_roc_detector.vcd");
        $dumpvars(0, tb_roc_detector);

        rst_n      = 0;
        resist_in  = 0;
        valid_in   = 0;
        roc_thresh = 1000; // 1 kΩ threshold

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== roc_detector testbench ===");

        // Test 1: Reset state
        if (roc_alarm !== 0 || delta_r !== 0) begin
            $error("TEST 1 FAIL: reset state");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 1 PASS: reset state verified");
            pass_cnt = pass_cnt + 1;
        end

        // Test 2: Sample 1 (10000) - first sample, no alarm
        send_sample(32'd10000);
        #1;
        if (roc_alarm !== 0 || delta_r !== 0) begin
            $error("TEST 2 FAIL: first sample should have delta 0 and no alarm");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2 PASS: first sample handled correctly");
            pass_cnt = pass_cnt + 1;
        end

        // Test 3: Sample 2 (10500) - delta 500 <= thresh 1000 -> no alarm
        send_sample(32'd10500);
        #1;
        if (roc_alarm !== 0 || delta_r !== 32'd500) begin
            $error("TEST 3 FAIL: delta=500 <= 1000, got delta=%0d alarm=%b", delta_r, roc_alarm);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3 PASS: delta 500 below threshold");
            pass_cnt = pass_cnt + 1;
        end

        // Test 4: Sample 3 (12000) - delta 1500 > thresh 1000 -> ALARM
        send_sample(32'd12000);
        #1;
        if (roc_alarm !== 1'b1 || delta_r !== 32'd1500) begin
            $error("TEST 4 FAIL: delta=1500 > 1000, got delta=%0d alarm=%b", delta_r, roc_alarm);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 4 PASS: delta 1500 triggered alarm");
            pass_cnt = pass_cnt + 1;
        end

        // Test 5: Sample 4 (12200) - delta 200 <= thresh 1000 -> alarm clears
        send_sample(32'd12200);
        #1;
        if (roc_alarm !== 0 || delta_r !== 32'd200) begin
            $error("TEST 5 FAIL: delta=200 <= 1000, got delta=%0d alarm=%b", delta_r, roc_alarm);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 5 PASS: small delta cleared alarm");
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
