// =============================================================================
// Gas Sensing System — UART TX Testbench
// Verifies bit-timing and byte order for 115200 baud / 100 MHz clock
// =============================================================================
`timescale 1ns / 1ps

module tb_uart_tx;

    localparam CLK_FREQ = 100_000_000;
    localparam BAUD     = 115_200;
    localparam BIT_NS   = 1_000_000_000 / BAUD;  // ~8680 ns per bit

    reg  clk = 0;
    reg  rst = 1;
    reg  [7:0] data_in;
    reg        data_valid;
    wire       tx_ready;
    wire       tx;

    always #5 clk = ~clk;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) dut (
        .clk        (clk),
        .rst        (rst),
        .data_in    (data_in),
        .data_valid (data_valid),
        .tx_ready   (tx_ready),
        .tx         (tx)
    );

    // Receive and decode a byte from the tx line
    task receive_byte;
        output [7:0] received;
        integer bit_idx;
        reg [7:0] rx_shift;
        begin
            // Wait for start bit (falling edge on tx)
            @(negedge tx);
            #(BIT_NS / 2);  // Sample in middle of start bit — should be 0
            if (tx !== 1'b0) $display("ERROR: Start bit not 0");
            rx_shift = 8'h0;
            for (bit_idx = 0; bit_idx < 8; bit_idx = bit_idx + 1) begin
                #BIT_NS;
                rx_shift[bit_idx] = tx;  // LSB first
            end
            #BIT_NS;  // Stop bit
            if (tx !== 1'b1) $display("ERROR: Stop bit not 1");
            received = rx_shift;
        end
    endtask

    task send_byte;
        input [7:0] byte_val;
        begin
            @(posedge clk);
            while (!tx_ready) @(posedge clk);
            data_in    = byte_val;
            data_valid = 1'b1;
            @(posedge clk); #1;
            data_valid = 1'b0;
        end
    endtask

    reg [7:0] rxd;
    integer   i;
    reg [7:0] test_bytes [0:4];

    initial begin
        $dumpfile("tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);

        data_valid = 0;
        data_in    = 8'h0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // Test 1: Transmit ASCII 'H' (0x48) and verify
        test_bytes[0] = 8'h48;  // 'H'
        test_bytes[1] = 8'h65;  // 'e'
        test_bytes[2] = 8'h6C;  // 'l'
        test_bytes[3] = 8'h6C;  // 'l'
        test_bytes[4] = 8'h6F;  // 'o'

        for (i = 0; i < 5; i = i + 1) begin
            fork
                send_byte(test_bytes[i]);
                receive_byte(rxd);
            join
            if (rxd === test_bytes[i])
                $display("PASS: byte %0d: tx=0x%02x rx=0x%02x ('%c')", i, test_bytes[i], rxd, rxd);
            else
                $display("FAIL: byte %0d: tx=0x%02x rx=0x%02x", i, test_bytes[i], rxd);
        end

        #(BIT_NS * 5);
        $display("--- UART TX testbench done ---");
        $finish;
    end

endmodule
