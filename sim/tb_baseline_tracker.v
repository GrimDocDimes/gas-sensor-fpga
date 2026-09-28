`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_baseline_tracker
// DUT       : baseline_tracker
// Simulator : Icarus Verilog (iverilog)
// =============================================================================
module tb_baseline_tracker;

    localparam CLK_PERIOD = 20; // 50 MHz
    localparam DATA_WIDTH = 32;

    reg                   clk, rst_n;
    reg  [DATA_WIDTH-1:0] resist_in;
    reg                   valid_in;
    reg  [3:0]            alpha_shift;
    reg                   reset_base;
    wire [DATA_WIDTH-1:0] baseline_out;
    wire                  baseline_vld;

    baseline_tracker #(
        .DATA_WIDTH(DATA_WIDTH),
        .ALPHA_W   (4)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .resist_in   (resist_in),
        .valid_in    (valid_in),
        .alpha_shift (alpha_shift),
        .reset_base  (reset_base),
        .baseline_out(baseline_out),
        .baseline_vld(baseline_vld)
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
        $dumpfile("tb_baseline_tracker.vcd");
        $dumpvars(0, tb_baseline_tracker);

        rst_n       = 0;
        resist_in   = 0;
        valid_in    = 0;
        alpha_shift = 4; // alpha = 1/16
        reset_base  = 0;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== baseline_tracker testbench ===");

        // Test 1: Reset state
        if (baseline_vld !== 0 || baseline_out !== 0) begin
            $error("TEST 1 FAIL: reset state");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 1 PASS: reset state verified");
            pass_cnt = pass_cnt + 1;
        end

        // Test 2: First sample cold-start seed
        send_sample(32'd10000);
        #1;
        if (baseline_vld !== 1'b1 || baseline_out !== 32'd10000) begin
            $error("TEST 2 FAIL: cold start seed, got %0d, exp 10000", baseline_out);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2 PASS: cold-start seeded to 10000");
            pass_cnt = pass_cnt + 1;
        end

        // Test 3: Second sample EMA update (step change to 20000, shift=4 -> +625)
        send_sample(32'd20000);
        #1;
        // 10000 + ((20000 - 10000) >> 4) = 10000 + 625 = 10625
        if (baseline_out !== 32'd10625) begin
            $error("TEST 3 FAIL: EMA update 1, got %0d, exp 10625", baseline_out);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3 PASS: EMA update 1 correctly updated to 10625");
            pass_cnt = pass_cnt + 1;
        end

        // Test 4: Re-seed via reset_base
        @(posedge clk);
        reset_base <= 1'b1;
        @(posedge clk);
        reset_base <= 1'b0;
        #1;
        if (baseline_vld !== 1'b0) begin
            $error("TEST 4 FAIL: baseline_vld should be 0 after reset_base");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 4 PASS: reset_base cleared baseline_vld");
            pass_cnt = pass_cnt + 1;
        end

        // Test 5: Re-seed on next sample
        send_sample(32'd50000);
        #1;
        if (baseline_vld !== 1'b1 || baseline_out !== 32'd50000) begin
            $error("TEST 5 FAIL: re-seeded value, got %0d, exp 50000", baseline_out);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 5 PASS: re-seeded directly to 50000");
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
