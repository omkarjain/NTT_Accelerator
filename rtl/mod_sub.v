// ---------------------------------------------------------------------
// mod_sub: combinational (a - b) mod Q, for 0 <= a,b < Q < 2^W
// Single conditional add-back -- correct because -Q < a-b < Q.
// ---------------------------------------------------------------------
module mod_sub #(
    parameter integer Q = 3329,
    parameter integer W = 12
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] diff
);
    wire signed [W+1:0] d = $signed({2'b0, a}) - $signed({2'b0, b});
    wire signed [W+1:0] d_fix = d[W+1] ? (d + Q) : d;
    assign diff = d_fix[W-1:0];
endmodule
