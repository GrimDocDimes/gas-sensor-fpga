// =============================================================================
// Gas Sensing System — XADC Wrapper Testbench
// =============================================================================
`timescale 1ns / 1ps

module tb_xadc_gas_wrapper;

    reg  clk = 0;
    reg  rst = 1;
    reg  vauxp6 = 0;
    reg  vauxn6 = 0;

    wire [11:0] adc_code;
    wire        data_valid;

    always #5 clk = ~clk;   // 100 MHz

    xadc_gas_wrapper dut (
        .clk        (clk),
        .rst        (rst),
        .vauxp6     (vauxp6),
        .vauxn6     (vauxn6),
        .adc_code   (adc_code),
        .data_valid (data_valid)
    );

    integer valid_count = 0;

    always @(posedge clk) begin
        if (data_valid) begin
            valid_count <= valid_count + 1;
            $display("[%0t ns] XADC valid pulse #%0d, adc_code = 0x%03x (%0d)",
                     $time, valid_count, adc_code, adc_code);
        end
    end

    initial begin
        $dumpfile("tb_xadc_gas_wrapper.vcd");
        $dumpvars(0, tb_xadc_gas_wrapper);

        // Hold reset for 100 ns
        repeat (10) @(posedge clk);
        rst = 0;
        $display("[%0t ns] Reset released", $time);

        // Wait for a few valid pulses (XADC simulation converts in ~26 cycles of ADCCLK)
        // At 100MHz system / 4 divider → 25MHz ADCCLK; ~1 µs per conversion
        #200_000;  // 200 µs

        if (valid_count >= 1)
            $display("PASS: Got %0d valid ADC pulses", valid_count);
        else
            $display("FAIL: No valid ADC pulse received");

        $finish;
    end

endmodule
