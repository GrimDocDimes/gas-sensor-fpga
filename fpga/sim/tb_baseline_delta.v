// =============================================================================
// Gas Sensing System — Baseline + Delta Logic Testbench
// =============================================================================
`timescale 1ns / 1ps

module tb_baseline_delta;

    reg  clk = 0;
    reg  rst = 1;
    reg  [11:0] adc_code  = 0;
    reg         adc_valid = 0;
    reg         btn_capture = 0;

    wire [11:0] r_air;
    wire [11:0] r_gas;
    wire [12:0] delta;
    wire [15:0] sensitivity;
    wire        baseline_valid;
    wire        result_valid;

    always #5 clk = ~clk;   // 100 MHz

    baseline_delta #(.USE_DIVIDER_IP(0)) dut (
        .clk            (clk),
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

    // Helper task: inject one ADC valid sample
    task inject_sample;
        input [11:0] code;
        begin
            adc_code  = code;
            adc_valid = 1'b1;
            @(posedge clk); #1;
            adc_valid = 1'b0;
        end
    endtask

    // Helper task: press baseline button
    task press_baseline;
        begin
            btn_capture = 1'b1;
            @(posedge clk); #1;
            btn_capture = 1'b0;
        end
    endtask

    integer pass = 0, fail = 0;

    task check;
        input [12:0] expected_delta;
        input [127:0] label;
        begin
            // Wait for result_valid
            @(posedge result_valid); @(posedge clk); #1;
            if (delta === expected_delta) begin
                $display("PASS [%s]: delta = %0d (expected %0d)", label, $signed(delta), $signed(expected_delta));
                pass = pass + 1;
            end else begin
                $display("FAIL [%s]: delta = %0d (expected %0d)", label, $signed(delta), $signed(expected_delta));
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_baseline_delta.vcd");
        $dumpvars(0, tb_baseline_delta);

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // ---- Test 1: baseline = 1000, sample = 1200, expected delta = +200 ----
        inject_sample(12'd1000);
        press_baseline;
        inject_sample(12'd1200);
        #100;  // give divider time
        if ($signed(delta) === 13'sd200)
            $display("PASS: Test 1 delta = +200"); else $display("FAIL: Test 1 delta = %0d", $signed(delta));

        // ---- Test 2: sample below baseline → negative delta ----
        inject_sample(12'd800);
        #100;
        if ($signed(delta) === -13'sd200)
            $display("PASS: Test 2 delta = -200"); else $display("FAIL: Test 2 delta = %0d", $signed(delta));

        // ---- Test 3: re-baseline ----
        inject_sample(12'd2000);
        press_baseline;
        inject_sample(12'd2100);
        #100;
        if ($signed(delta) === 13'sd100)
            $display("PASS: Test 3 delta = +100"); else $display("FAIL: Test 3 delta = %0d", $signed(delta));

        // ---- Test 4: zero delta ----
        inject_sample(12'd2000);
        #100;
        if ($signed(delta) === 13'sd0)
            $display("PASS: Test 4 delta = 0"); else $display("FAIL: Test 4 delta = %0d", $signed(delta));

        $display("\n--- Simulation done. (Note: sensitivity output depends on divider latency) ---");
        $finish;
    end

endmodule
