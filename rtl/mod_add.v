// ---------------------------------------------------------------------
// mod_add: combinational (a + b) mod Q, for 0 <= a,b < Q < 2^W
// Single conditional subtract -- correct because a+b < 2Q.
// ---------------------------------------------------------------------
module mod_add #(
    parameter integer Q = 3329,
    parameter integer W = 12
) (
    input  wire [W-1:0] a,
    input  wire [W-1:0] b,
    output wire [W-1:0] sum
);
    wire [W:0] s = {1'b0, a} + {1'b0, b};
    wire [W:0] s_minus_q = s - Q;
    assign sum = s_minus_q[W] ? s[W-1:0] : s_minus_q[W-1:0];
endmodule
