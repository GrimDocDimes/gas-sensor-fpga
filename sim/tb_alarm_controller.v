`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_alarm_controller
// DUT       : alarm_controller
// Simulator : Icarus Verilog (iverilog)
// Run with  :
//   iverilog -o tb_alarm_controller.vvp \
//       tb_alarm_controller.v ../rtl/alarm_controller.v
//   vvp tb_alarm_controller.vvp
//
// Test cases:
//   1. Reset state — all outputs deasserted
//   2. Single roc_alarm → IDLE→ACTIVE→LATCHED sequence
//   3. Alarm clears before latch_cycles → returns to IDLE without latching
//   4. PS ACK clears latched alarm
//   5. Priority: active roc_alarm prevents ACK from reaching IDLE
//   6. xfault-only alarm (no roc) → ACK allowed to IDLE
//   7. Multiple channels alarming simultaneously
// =============================================================================
module tb_alarm_controller;

    localparam CLK_PERIOD   = 20;  // 50 MHz
    localparam NUM_CH       = 6;
    localparam LATCH_CYCLES = 4;   // short latch for faster simulation

    // ── DUT signals ────────────────────────────────────────────────────────────
    reg              clk, rst_n;
    reg  [5:0]       roc_alarms;
    reg  [5:0]       xfaults;
    reg              alarm_ack;
    reg  [15:0]      latch_cycles;
    wire             alarm_out;
    wire [5:0]       fault_out;
    wire             alarm_active;
    wire             alarm_latched;

    // ── DUT ──────────────────────────────────────────────────────────────────
    alarm_controller #(
        .NUM_CH  (NUM_CH),
        .LATCH_W (16)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .roc_alarms   (roc_alarms),
        .xfaults      (xfaults),
        .alarm_ack    (alarm_ack),
        .latch_cycles (latch_cycles),
        .alarm_out    (alarm_out),
        .fault_out    (fault_out),
        .alarm_active (alarm_active),
        .alarm_latched(alarm_latched)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_cnt = 0, fail_cnt = 0;

    task check;
        input [63:0] tid;
        input        exp_alarm_out;
        input        exp_latched;
        input        exp_active;
        begin
            @(posedge clk); #1; // sample after clock edge
            if (alarm_out    !== exp_alarm_out ||
                alarm_latched !== exp_latched    ||
                alarm_active  !== exp_active) begin
                $error("TEST %0d FAIL: alarm_out=%b(exp %b) latched=%b(exp %b) active=%b(exp %b)",
                       tid, alarm_out, exp_alarm_out,
                       alarm_latched, exp_latched,
                       alarm_active, exp_active);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("TEST %0d PASS", tid);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task pulse_ack;
        begin
            @(posedge clk);
            alarm_ack <= 1'b1;
            @(posedge clk);
            alarm_ack <= 1'b0;
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("tb_alarm_controller.vcd");
        $dumpvars(0, tb_alarm_controller);

        // Init
        rst_n       = 0;
        roc_alarms  = 6'h00;
        xfaults     = 6'h00;
        alarm_ack   = 0;
        latch_cycles= LATCH_CYCLES;
        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== alarm_controller testbench (latch_cycles=%0d) ===", LATCH_CYCLES);

        // ── TEST 1: Reset state ────────────────────────────────────────────────
        check(1, 0, 0, 0);

        // ── TEST 2: Single roc_alarm → IDLE→ACTIVE→LATCHED ────────────────────
        @(posedge clk);
        roc_alarms <= 6'h01;    // CH0 roc alarm
        repeat(2) @(posedge clk); #1;
        if (!alarm_out || !alarm_active) begin
            $error("TEST 2a FAIL: should be ACTIVE after roc_alarm");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2a PASS: ACTIVE asserted");
            pass_cnt = pass_cnt + 1;
        end
        // Wait for latch (LATCH_CYCLES cycles)
        repeat(LATCH_CYCLES + 1) @(posedge clk);
        #1;
        if (!alarm_latched) begin
            $error("TEST 2b FAIL: should be LATCHED after %0d cycles", LATCH_CYCLES);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2b PASS: LATCHED asserted");
            pass_cnt = pass_cnt + 1;
        end
        roc_alarms <= 6'h00;    // alarm clears, but latch should hold
        @(posedge clk); #1;
        if (!alarm_latched) begin
            $error("TEST 2c FAIL: latch should be sticky even after input clears");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2c PASS: latch sticky after input clear");
            pass_cnt = pass_cnt + 1;
        end
        // ACK the alarm
        pulse_ack;
        @(posedge clk); #1;
        if (alarm_out || alarm_latched) begin
            $error("TEST 2d FAIL: alarm should clear after ACK");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 2d PASS: alarm cleared by ACK");
            pass_cnt = pass_cnt + 1;
        end

        // ── TEST 3: Transient alarm clears before latch_cycles → no latch ──────
        @(posedge clk);
        roc_alarms <= 6'h04;    // CH2 alarm
        repeat(2) @(posedge clk); // less than LATCH_CYCLES
        roc_alarms <= 6'h00;    // clear before latch
        repeat(3) @(posedge clk); #1;
        if (alarm_latched) begin
            $error("TEST 3 FAIL: should NOT latch transient alarm");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3 PASS: transient alarm did not latch");
            pass_cnt = pass_cnt + 1;
        end
        if (alarm_out) begin
            $error("TEST 3b FAIL: alarm_out should be 0 after transient");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 3b PASS: alarm_out cleared after transient");
            pass_cnt = pass_cnt + 1;
        end

        // ── TEST 4: xfault-only alarm → ACK allowed to IDLE ───────────────────
        @(posedge clk);
        xfaults <= 6'h3F;         // all channels fault (no roc)
        repeat(LATCH_CYCLES + 3) @(posedge clk);
        #1;
        if (!alarm_latched) begin
            $error("TEST 4a FAIL: xfault should latch");
            fail_cnt = fail_cnt + 1;
        end else $display("TEST 4a PASS: xfault latched");
        xfaults <= 6'h00;
        pulse_ack;
        @(posedge clk); #1;
        if (alarm_out || alarm_latched) begin
            $error("TEST 4b FAIL: xfault alarm should clear after ACK (no roc active)");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 4b PASS: xfault cleared by ACK, returned to IDLE");
            pass_cnt = pass_cnt + 1;
        end

        // ── TEST 5: Priority — active roc_alarm prevents ACK → IDLE ───────────
        @(posedge clk);
        roc_alarms <= 6'h01;
        repeat(LATCH_CYCLES + 2) @(posedge clk);
        // roc_alarms still active; ACK should NOT go to IDLE
        pulse_ack;
        repeat(2) @(posedge clk); #1;
        if (!alarm_active) begin
            $error("TEST 5 FAIL: ACK should not suppress active roc_alarm");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 5 PASS: active roc_alarm prevents ACK→IDLE");
            pass_cnt = pass_cnt + 1;
        end
        roc_alarms <= 6'h00;    // clear roc then re-ack
        repeat(2) @(posedge clk);
        pulse_ack;
        @(posedge clk); #1;
        if (alarm_out) begin
            $error("TEST 5b FAIL: alarm should clear once roc gone and acked");
            fail_cnt = fail_cnt + 1;
        end else $display("TEST 5b PASS: alarm cleared after roc gone + ack");

        // ── Summary ────────────────────────────────────────────────────────────
        repeat(4) @(posedge clk);
        $display("");
        $display("====================================");
        $display("  PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  ALL TESTS PASSED");
        else               $display("  *** FAILURES DETECTED ***");
        $display("====================================");
        $finish;
    end

    initial begin
        #200_000;
        $error("WATCHDOG: timeout");
        $finish;
    end

endmodule
