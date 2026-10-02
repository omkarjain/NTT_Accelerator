// ---------------------------------------------------------------------
// zeta_sched: wraps zeta_rom with a "fetch once per group, hold and
// reuse" policy, exposed via a simple valid handshake so the FSM never
// needs to hardcode ROM pipeline latency.
//
//   - When `new_group` pulses (from addr_gen, at j==0 of every group),
//     zeta_sched issues a ROM read for `zeta_idx` and drives
//     `zeta_valid` low until the new value has landed in `zeta_cur`
//     (2 cycles: 1 for the ROM's registered output, 1 to latch it).
//   - On every other cycle (mid-group), the previously loaded zeta is
//     still correct, so `zeta_valid` stays high and `zeta_cur` is
//     simply held.
// ---------------------------------------------------------------------
module zeta_sched #(
    parameter integer N   = 256,
    parameter integer W   = 12,
    parameter integer ZAW = 7,
    parameter         INITFILE = "zetas_N256.mem"
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            new_group,      // pulse: begin fetching a fresh zeta
    input  wire [ZAW-1:0]  zeta_idx,       // index to fetch when new_group pulses
    output reg  [W-1:0]    zeta_cur,       // held zeta value, valid for the whole group
    output wire             zeta_valid      // 0 while a fetch triggered by new_group is in flight
);
    wire [W-1:0] rom_zeta;

    zeta_rom #(.N(N), .W(W), .AW(ZAW), .INITFILE(INITFILE)) u_rom (
        .clk  (clk),
        .addr (zeta_idx),
        .zeta (rom_zeta)
    );

    reg fetch_stage1;   // ROM read issued, waiting for its registered output
    reg fetch_stage2;   // ROM output valid this cycle, latch it into zeta_cur

    // zeta_valid is combinational: it must drop in the SAME cycle
    // new_group first pulses (not one cycle later), otherwise the FSM
    // can sample a stale zeta_valid==1 left over from the previous group
    // and race ahead with the old zeta_cur value.
    assign zeta_valid = !(new_group || fetch_stage1 || fetch_stage2);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_stage1 <= 1'b0;
            fetch_stage2 <= 1'b0;
            zeta_cur     <= {W{1'b0}};
        end else begin
            fetch_stage1 <= new_group;
            fetch_stage2 <= fetch_stage1;

            if (fetch_stage2)
                zeta_cur <= rom_zeta;
        end
    end
endmodule
