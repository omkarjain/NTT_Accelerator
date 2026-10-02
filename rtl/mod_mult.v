// ---------------------------------------------------------------------
// mod_mult: registered (a * b) mod Q, 1-cycle latency.
//
// Behavioral reduction (%% by a compile-time-constant Q) is used here for
// design clarity and functional correctness; Vivado will constant-fold
// this into a combinational reduction network. For a higher-Fmax /
// lower-LUT implementation, swap this module's internals for a Barrett
// or Montgomery reduction (the port list is unchanged, so it drops in
// transparently -- see README "Optimization notes").
// ---------------------------------------------------------------------
module mod_mult #(
    parameter integer Q = 3329,
    parameter integer W = 12
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [W-1:0]     a,
    input  wire [W-1:0]     b,
    output reg  [W-1:0]     p,
    output reg              p_valid
);
    wire [2*W-1:0] prod = a * b;
    wire [W-1:0]   prod_mod = prod % Q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p       <= {W{1'b0}};
            p_valid <= 1'b0;
        end else begin
            p_valid <= en;
            if (en)
                p <= prod_mod;
        end
    end
endmodule
