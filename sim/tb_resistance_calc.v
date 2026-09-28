`timescale 1ns/1ps
// =============================================================================
// Testbench : tb_resistance_calc
// DUT       : resistance_calc (and div_pipe)
// Simulator : Icarus Verilog (iverilog)
// Run with  :
//   iverilog -o tb_resistance_calc.vvp \
//       tb_resistance_calc.v ../rtl/resistance_calc.v ../rtl/div_pipe.v
//   vvp tb_resistance_calc.vvp
//
// Test cases:
//   1. Equal resistors (code = CODE_FS/2) → R = R_KNOWN
//   2. code = 0                           → SC sentinel (R = 0)
//   3. code >= CODE_FS                    → OC sentinel (R = 32'hFFFF_FFFF)
//   4. code = CODE_FS/4                   → R = R_KNOWN/3 ≈ 3333 Ω
//   5. code = 3*CODE_FS/4                 → R = 3*R_KNOWN ≈ 30000 Ω
//   6. Reset mid-operation                → outputs cleared, no stale data
//   7. Back-to-back valid pulses          → sequential results (check FIFO-free)
//
// Checks : $error (self-checking) + PASS/FAIL summary
// =============================================================================
module tb_resistance_calc;

    // ── Parameters matching DUT ────────────────────────────────────────────────
    localparam CLK_PERIOD  = 20;    // 50 MHz
    localparam R_KNOWN     = 10_000;
    localparam CODE_W      = 12;
    localparam RESULT_W    = 32;
    localparam CODE_FS_VAL = 12'd2730; // ≈ (1.365/2.730) × 4095 representative
    localparam DIV_LATENCY = 27;    // DIVIDEND_BITS(26)+1 cycles

    // ── DUT signals ────────────────────────────────────────────────────────────
    reg                  clk, rst_n;
    reg  [CODE_W-1:0]    code_fs;
    reg  [CODE_W-1:0]    code_in;
    reg                  valid_in;
    wire [RESULT_W-1:0]  resist_out;
    wire                 valid_out;
    wire                 oc_flag;
    wire                 sc_flag;

    // ── DUT instantiation ──────────────────────────────────────────────────────
    resistance_calc #(
        .R_KNOWN      (R_KNOWN),
        .CODE_WIDTH   (CODE_W),
        .RESULT_WIDTH (RESULT_W)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .code_fs    (code_fs),
        .code_in    (code_in),
        .valid_in   (valid_in),
        .resist_out (resist_out),
        .valid_out  (valid_out),
        .oc_flag    (oc_flag),
        .sc_flag    (sc_flag)
    );

    // ── Clock ─────────────────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ── Scoreboard ────────────────────────────────────────────────────────────
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // Tolerance for fixed-point integer rounding: ±1 Ω
    localparam TOL = 1;

    task check_result;
        input [RESULT_W-1:0] expected_r;
        input                expected_oc;
        input                expected_sc;
        input [63:0]         test_id;
        integer wait_cyc;
        begin
            wait_cyc = 0;
            // Wait for valid_out (with timeout)
            while (!valid_out && wait_cyc < DIV_LATENCY + 5) begin
                @(posedge clk);
                wait_cyc = wait_cyc + 1;
            end
            if (!valid_out) begin
                $error("TEST %0d: TIMEOUT — valid_out never asserted", test_id);
                fail_cnt = fail_cnt + 1;
            end else if (expected_oc && !oc_flag) begin
                $error("TEST %0d: Expected OC flag, got oc_flag=%b sc_flag=%b R=%0d",
                       test_id, oc_flag, sc_flag, resist_out);
                fail_cnt = fail_cnt + 1;
            end else if (expected_sc && !sc_flag) begin
                $error("TEST %0d: Expected SC flag, got oc_flag=%b sc_flag=%b R=%0d",
                       test_id, oc_flag, sc_flag, resist_out);
                fail_cnt = fail_cnt + 1;
            end else if (!expected_oc && !expected_sc &&
                         (resist_out < expected_r - TOL || resist_out > expected_r + TOL)) begin
                $error("TEST %0d: R=%0d expected=%0d (±%0d), FAIL",
                       test_id, resist_out, expected_r, TOL);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("TEST %0d: PASS  R=%0d expected≈%0d  oc=%b sc=%b",
                         test_id, resist_out, expected_r, oc_flag, sc_flag);
                pass_cnt = pass_cnt + 1;
            end
            @(posedge clk); // consume valid_out cycle
        end
    endtask

    task send_sample;
        input [CODE_W-1:0] code;
        begin
            @(posedge clk);
            code_in  <= code;
            valid_in <= 1'b1;
            @(posedge clk);
            valid_in <= 1'b0;
        end
    endtask

    // ── Test stimulus ──────────────────────────────────────────────────────────
    integer i;
    integer expected_r;
    integer code_val;

    initial begin
        $dumpfile("tb_resistance_calc.vcd");
        $dumpvars(0, tb_resistance_calc);

        // Init
        rst_n    = 0;
        code_fs  = CODE_FS_VAL;
        code_in  = 0;
        valid_in = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("=== resistance_calc testbench ===");
        $display("R_KNOWN=%0d  CODE_FS=%0d", R_KNOWN, CODE_FS_VAL);

        // ── TEST 1: Equal resistors (code = CODE_FS/2) → R ≈ R_KNOWN ──────────
        // With code = CODE_FS/2: R = R_KNOWN × (FS/2) / (FS - FS/2) = R_KNOWN
        code_val = CODE_FS_VAL / 2;
        send_sample(code_val[CODE_W-1:0]);
        // Expected: R_KNOWN × code / (CODE_FS - code) = 10000 × 1365 / 1365 = 10000
        expected_r = R_KNOWN; // exactly 10000
        check_result(expected_r, 0, 0, 1);

        // ── TEST 2: Short circuit (code = 0) → SC flag ────────────────────────
        send_sample(12'd0);
        check_result(0, 0, 1, 2);

        // ── TEST 3: Open circuit (code = CODE_FS) → OC flag ───────────────────
        send_sample(CODE_FS_VAL);
        check_result(32'hFFFF_FFFF, 1, 0, 3);

        // ── TEST 4: code = CODE_FS/4 → R = R_KNOWN/3 ≈ 3333 Ω ────────────────
        // R = 10000 × (FS/4) / (FS - FS/4) = 10000 × 1/3 ≈ 3333
        code_val = CODE_FS_VAL / 4;
        send_sample(code_val[CODE_W-1:0]);
        expected_r = (R_KNOWN * (CODE_FS_VAL/4)) / (CODE_FS_VAL - CODE_FS_VAL/4);
        check_result(expected_r, 0, 0, 4);

        // ── TEST 5: code = 3*CODE_FS/4 → R = 3*R_KNOWN ≈ 30000 Ω ─────────────
        code_val = (3 * CODE_FS_VAL) / 4;
        send_sample(code_val[CODE_W-1:0]);
        expected_r = (R_KNOWN * ((3*CODE_FS_VAL)/4)) / (CODE_FS_VAL - (3*CODE_FS_VAL)/4);
        check_result(expected_r, 0, 0, 5);

        // ── TEST 6: Reset mid-operation ────────────────────────────────────────
        // Send a valid, then immediately reset before result arrives
        code_val = CODE_FS_VAL / 2;
        @(posedge clk);
        code_in  <= code_val[CODE_W-1:0];
        valid_in <= 1'b1;
        @(posedge clk);
        valid_in <= 1'b0;
        // Assert reset after 3 cycles
        repeat(3) @(posedge clk);
        rst_n <= 0;
        repeat(2) @(posedge clk);
        rst_n <= 1;
        // After reset, valid_out should NOT fire with stale data
        // (division is aborted by reset)
        repeat(DIV_LATENCY + 5) @(posedge clk);
        if (valid_out) begin
            $error("TEST 6: FAIL — stale valid_out after reset");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("TEST 6: PASS  no stale output after reset");
            pass_cnt = pass_cnt + 1;
        end

        // ── TEST 7: Randomized stimulus ────────────────────────────────────────
        $display("--- Randomized test (10 cases) ---");
        repeat(10) begin : rand_loop
            integer rcode, rexpected;
            rcode = $urandom_range(1, CODE_FS_VAL - 1);
            rexpected = (R_KNOWN * rcode) / (CODE_FS_VAL - rcode);
            send_sample(rcode[CODE_W-1:0]);
            check_result(rexpected, 0, 0, 7);
        end

        // ── Final summary ──────────────────────────────────────────────────────
        $display("");
        $display("====================================");
        $display("  PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  *** FAILURES DETECTED ***");
        $display("====================================");
        $finish;
    end

    // ── Watchdog ──────────────────────────────────────────────────────────────
    initial begin
        #500_000;
        $error("WATCHDOG: Simulation exceeded 500us — possible hang");
        $finish;
    end

endmodule
