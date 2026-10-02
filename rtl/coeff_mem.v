// ---------------------------------------------------------------------
// coeff_mem: true dual-port RAM holding the N ring coefficients.
// Port A and Port B are used simultaneously by the FSM to fetch/store
// the two operands a[j] and a[j+len] of a butterfly in the same cycle.
// Synchronous read (1-cycle read latency) -- standard inferred
// block-RAM style for Vivado.
// External load/unload also goes through these two ports (see ntt_top).
// ---------------------------------------------------------------------
module coeff_mem #(
    parameter integer N  = 256,
    parameter integer W  = 12,
    parameter integer AW = 8          // = clog2(N)
) (
    input  wire             clk,

    input  wire             a_we,
    input  wire [AW-1:0]    a_addr,
    input  wire [W-1:0]     a_wdata,
    output reg  [W-1:0]     a_rdata,

    input  wire             b_we,
    input  wire [AW-1:0]    b_addr,
    input  wire [W-1:0]     b_wdata,
    output reg  [W-1:0]     b_rdata
);
    reg [W-1:0] mem [0:N-1];

    always @(posedge clk) begin
        if (a_we)
            mem[a_addr] <= a_wdata;
        a_rdata <= a_we ? a_wdata : mem[a_addr]; // write-first on this port
    end

    always @(posedge clk) begin
        if (b_we)
            mem[b_addr] <= b_wdata;
        b_rdata <= b_we ? b_wdata : mem[b_addr]; // write-first on this port
    end
endmodule
