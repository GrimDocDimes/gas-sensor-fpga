// =============================================================================
// Gas Sensing System — 4-bit Hex to 7-Segment Decoder
// Board:  Nexys 4 DDR / Artix-7 XC7A100T
//
// Nexys 4 DDR uses ACTIVE-LOW cathodes (CA–CG, DP) and ACTIVE-LOW anodes (AN).
// This module outputs active-low segment bits for a given 4-bit hex digit.
//
// Segment mapping (standard):
//       aaa
//      f   b
//      f   b
//       ggg
//      e   c
//      e   c
//       ddd   .dp
//
// Output seg[6:0] = {CA, CB, CC, CD, CE, CF, CG}
//   (active-low: 0 = segment ON)
// =============================================================================

`timescale 1ns / 1ps

module seg7_decoder (
    input  wire [3:0] digit,    // 4-bit hex digit (0–F)
    output reg  [6:0] seg       // {CA,CB,CC,CD,CE,CF,CG} active-low
);

    // seg = {a, b, c, d, e, f, g} active-low (0 = ON)
    always @(*) begin
        case (digit)
            4'h0: seg = 7'b000_0001;  // 0
            4'h1: seg = 7'b100_1111;  // 1
            4'h2: seg = 7'b001_0010;  // 2
            4'h3: seg = 7'b000_0110;  // 3
            4'h4: seg = 7'b100_1100;  // 4
            4'h5: seg = 7'b010_0100;  // 5
            4'h6: seg = 7'b010_0000;  // 6
            4'h7: seg = 7'b000_1111;  // 7
            4'h8: seg = 7'b000_0000;  // 8
            4'h9: seg = 7'b000_0100;  // 9
            4'hA: seg = 7'b000_1000;  // A
            4'hB: seg = 7'b110_0000;  // b
            4'hC: seg = 7'b011_0001;  // C
            4'hD: seg = 7'b100_0010;  // d
            4'hE: seg = 7'b011_0000;  // E
            4'hF: seg = 7'b011_1000;  // F
            default: seg = 7'b111_1111;  // All off
        endcase
    end

endmodule
