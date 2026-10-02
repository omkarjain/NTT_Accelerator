// ---------------------------------------------------------------------
// addr_gen: walks the full incomplete-NTT iteration space
//
//   for s = 0 .. LOGN-2:                      // stage
//     len = N/2 >> s
//     for g = 0 .. (1<<s)-1:                  // group within stage
//       start = g * 2*len
//       zeta_idx = (1<<s) + g                 // matches golden model
//       for j = 0 .. len-1:                   // butterfly within group
//         addr_a = start + j
//         addr_b = addr_a + len
//
// and exposes the *current* (addr_a, addr_b, zeta_idx) plus a one-hot
// "new_group" strobe (j==0, so the zeta scheduler knows to fetch a fresh
// zeta) and a "last_bf" strobe (final butterfly of the whole transform).
// Advances one butterfly per `adv` pulse.
// ---------------------------------------------------------------------
module addr_gen #(
    parameter integer N   = 256,
    parameter integer AW  = 8,                 // = clog2(N)
    parameter integer ZAW = 7                  // = clog2(N/2)
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,              // pulse: reset iteration to (s=0,g=0,j=0)
    input  wire            adv,                // pulse: advance to next butterfly

    output wire [AW-1:0]   addr_a,
    output wire [AW-1:0]   addr_b,
    output wire [ZAW-1:0]  zeta_idx,
    output wire            new_group,          // ONE-SHOT pulse: this cycle starts a new group
    output wire            last_bf_in_group,   // this is the last j of the current group
    output wire            last_bf             // this is the very last butterfly overall
);
    localparam integer LOGN = $clog2(N);       // total stages if we went all the way to len=1
    localparam integer NSTAGES = LOGN - 1;     // incomplete NTT stops at len=2

    reg [AW-1:0] s_r;        // stage index, 0 .. NSTAGES-1
    reg [AW-1:0] g_r;        // group index within stage, 0 .. (1<<s)-1
    reg [AW-1:0] j_r;        // element index within group, 0 .. len-1
    reg [AW-1:0] len_r;      // N/2 >> s

    wire [AW-1:0] start_addr = g_r * (len_r << 1);
    wire [AW-1:0] pow2s      = {{(AW-1){1'b0}}, 1'b1} << s_r;   // 2^s_r
    wire [AW-1:0] group_last = pow2s - 1'b1;                    // (1<<s)-1

    assign addr_a   = start_addr + j_r;
    assign addr_b   = addr_a + len_r;
    assign zeta_idx = pow2s[ZAW-1:0] + g_r[ZAW-1:0];

    assign last_bf_in_group  = (j_r == len_r - 1'b1);
    assign last_bf            = last_bf_in_group &&
                                (g_r == group_last) &&
                                (s_r == NSTAGES[AW-1:0] - 1'b1);

    // new_group is a registered ONE-SHOT pulse: high for exactly the one
    // cycle after start/adv lands the counters on j==0 of a (possibly new)
    // group, and low on every other cycle -- including while the FSM
    // stalls at the same butterfly without pulsing adv. This guarantees
    // zeta_sched's fetch handshake always completes.
    reg new_group_r;
    assign new_group = new_group_r;

    wire will_wrap_group = adv && last_bf_in_group; // this adv rolls j back to 0

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_r         <= {AW{1'b0}};
            g_r         <= {AW{1'b0}};
            j_r         <= {AW{1'b0}};
            len_r       <= (N/2);
            new_group_r <= 1'b0;
        end else if (start) begin
            s_r         <= {AW{1'b0}};
            g_r         <= {AW{1'b0}};
            j_r         <= {AW{1'b0}};
            len_r       <= (N/2);
            new_group_r <= 1'b1;   // first group of the whole transform
        end else if (adv) begin
            if (j_r == len_r - 1'b1) begin
                j_r <= {AW{1'b0}};
                if (g_r == group_last) begin
                    g_r   <= {AW{1'b0}};
                    s_r   <= s_r + 1'b1;
                    len_r <= len_r >> 1;
                end else begin
                    g_r <= g_r + 1'b1;
                end
                new_group_r <= 1'b1;   // landed on j==0 of a new group
            end else begin
                j_r         <= j_r + 1'b1;
                new_group_r <= 1'b0;
            end
        end else begin
            new_group_r <= 1'b0;       // stall cycles: pulse already consumed
        end
    end
endmodule
