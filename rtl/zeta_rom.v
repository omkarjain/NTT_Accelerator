// ---------------------------------------------------------------------
// zeta_rom: precomputed twiddle-factor table.
//   zetas[i] = g^BitRev(i, log2(N)-1) mod Q,  i = 1 .. N/2-1
// where g is a primitive N-th root of unity mod Q. Index 0 is unused
// (never addressed by the address generator). Generated offline by
// scripts/gen_zetas.py and loaded via $readmemh at elaboration time.
// ---------------------------------------------------------------------
module zeta_rom #(
    parameter integer N       = 256,
    parameter integer W       = 12,
    parameter integer AW      = 7,               // = clog2(N/2)
    parameter         INITFILE = "zetas_N256.mem"
) (
    input  wire          clk,
    input  wire [AW-1:0] addr,
    output reg  [W-1:0]  zeta
);
    reg [W-1:0] rom [0:(N/2)-1];

    initial begin
        $readmemh(INITFILE, rom);
    end

    always @(posedge clk)
        zeta <= rom[addr];
endmodule
