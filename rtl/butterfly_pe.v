// ---------------------------------------------------------------------
// butterfly_pe: one Cooley-Tukey NTT butterfly (ML-KEM / Kyber form)
//
//   t      = zeta * b  mod Q
//   a_out  = a + t      mod Q
//   b_out  = a - t      mod Q
//
// Pipelined: `en` starts a butterfly; `out_valid` pulses one cycle later
// (matching mod_mult's 1-cycle latency) with a_out/b_out ready.
// `a_in` is carried through a matching delay register so it lines up
// with `t` when the adder/subtractor fire.
// ---------------------------------------------------------------------
module butterfly_pe #(
    parameter integer Q = 3329,
    parameter integer W = 12
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          en,
    input  wire [W-1:0]  a_in,
    input  wire [W-1:0]  b_in,
    input  wire [W-1:0]  zeta_in,
    output wire [W-1:0]  a_out,
    output wire [W-1:0]  b_out,
    output wire          out_valid
);
    // delay a_in by 1 cycle to match mod_mult's registered latency
    reg [W-1:0] a_dly;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) a_dly <= {W{1'b0}};
        else if (en) a_dly <= a_in;

    wire [W-1:0] t;
    wire         t_valid;

    mod_mult #(.Q(Q), .W(W)) u_mult (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .a       (zeta_in),
        .b       (b_in),
        .p       (t),
        .p_valid (t_valid)
    );

    mod_add #(.Q(Q), .W(W)) u_add (.a(a_dly), .b(t), .sum(a_out));
    mod_sub #(.Q(Q), .W(W)) u_sub (.a(a_dly), .b(t), .diff(b_out));

    assign out_valid = t_valid;
endmodule
