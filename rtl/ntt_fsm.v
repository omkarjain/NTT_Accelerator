// ---------------------------------------------------------------------
// ntt_fsm: top-level control FSM. Drives addr_gen / zeta_sched /
// coeff_mem / butterfly_pe through one butterfly at a time until the
// whole (log2(N)-1)-stage incomplete NTT has been computed in place.
//
// This is a straightforward, non-overlapped (one butterfly fully
// completes before the next starts) controller, prioritizing clarity
// and correctness. See README "Optimization notes" for how to overlap
// butterflies for higher throughput.
// ---------------------------------------------------------------------
module ntt_fsm #(
    parameter integer N        = 256,
    parameter integer Q        = 3329,
    parameter integer W        = 12,
    parameter integer AW       = 8,
    parameter integer ZAW      = 7,
    parameter          INITFILE = "zetas_N256.mem"
) (
    input  wire            clk,
    input  wire            rst_n,

    input  wire            i_start,
    output reg              o_busy,
    output reg              o_done,     // 1-cycle pulse when the transform completes

    // dual-port access into coeff_mem, granted to this FSM only while o_busy
    output wire             mem_a_we,
    output wire [AW-1:0]    mem_a_addr,
    output wire [W-1:0]     mem_a_wdata,
    input  wire [W-1:0]     mem_a_rdata,

    output wire             mem_b_we,
    output wire [AW-1:0]    mem_b_addr,
    output wire [W-1:0]     mem_b_wdata,
    input  wire [W-1:0]     mem_b_rdata
);
    // ---------------- address generator ----------------
    wire [AW-1:0]  addr_a, addr_b;
    wire [ZAW-1:0] zeta_idx;
    wire           new_group, last_bf_in_group, last_bf;
    reg            ag_start, ag_adv;

    addr_gen #(.N(N), .AW(AW), .ZAW(ZAW)) u_addr_gen (
        .clk    (clk), .rst_n (rst_n),
        .start  (ag_start), .adv (ag_adv),
        .addr_a (addr_a), .addr_b (addr_b), .zeta_idx (zeta_idx),
        .new_group (new_group),
        .last_bf_in_group (last_bf_in_group),
        .last_bf (last_bf)
    );

    // ---------------- zeta scheduler ----------------
    wire [W-1:0] zeta_cur;
    wire         zeta_valid;

    zeta_sched #(.N(N), .W(W), .ZAW(ZAW), .INITFILE(INITFILE)) u_zeta_sched (
        .clk (clk), .rst_n (rst_n),
        .new_group (new_group), .zeta_idx (zeta_idx),
        .zeta_cur (zeta_cur), .zeta_valid (zeta_valid)
    );

    // ---------------- butterfly PE ----------------
    reg          bf_en;
    wire [W-1:0] bf_a_out, bf_b_out;
    wire         bf_out_valid;

    butterfly_pe #(.Q(Q), .W(W)) u_bf (
        .clk (clk), .rst_n (rst_n), .en (bf_en),
        .a_in (mem_a_rdata), .b_in (mem_b_rdata), .zeta_in (zeta_cur),
        .a_out (bf_a_out), .b_out (bf_b_out), .out_valid (bf_out_valid)
    );

    reg [W-1:0] a_result, b_result;
    reg         last_bf_latched;

    // ---------------- memory port mux (only this FSM drives it) ----------------
    reg          we_pulse;
    assign mem_a_we    = we_pulse;
    assign mem_b_we    = we_pulse;
    assign mem_a_addr  = addr_a;
    assign mem_b_addr  = addr_b;
    assign mem_a_wdata = a_result;
    assign mem_b_wdata = b_result;

    // ---------------- FSM ----------------
    localparam S_IDLE     = 4'd0,
               S_START     = 4'd1,
               S_GWAIT     = 4'd2,
               S_READ      = 4'd3,
               S_COMPUTE   = 4'd4,
               S_CAPTURE   = 4'd5,
               S_WRITE     = 4'd6,
               S_ADV       = 4'd7,
               S_ADVWAIT   = 4'd9,   // buffer cycle: lets addr_gen register ag_adv's
                                     // effect (and new_group) before S_GWAIT samples
                                     // zeta_valid -- mirrors the buffer S_START already
                                     // provides for the very first group.
               S_DONE      = 4'd8;

    reg [3:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            o_busy          <= 1'b0;
            o_done          <= 1'b0;
            ag_start        <= 1'b0;
            ag_adv          <= 1'b0;
            bf_en           <= 1'b0;
            we_pulse        <= 1'b0;
            a_result        <= {W{1'b0}};
            b_result        <= {W{1'b0}};
            last_bf_latched <= 1'b0;
        end else begin
            // defaults (pulses deassert unless re-asserted below)
            ag_start <= 1'b0;
            ag_adv   <= 1'b0;
            bf_en    <= 1'b0;
            we_pulse <= 1'b0;
            o_done   <= 1'b0;

            case (state)
                S_IDLE: begin
                    o_busy <= 1'b0;
                    if (i_start) begin
                        o_busy   <= 1'b1;
                        ag_start <= 1'b1;
                        state    <= S_START;
                    end
                end

                S_START: begin
                    // one cycle for addr_gen to register its reset counters
                    state <= S_GWAIT;
                end

                S_GWAIT: begin
                    // wait until zeta_sched has a valid zeta for this group
                    last_bf_latched <= last_bf;
                    if (zeta_valid)
                        state <= S_READ;
                end

                S_READ: begin
                    // one cycle for coeff_mem's synchronous read to settle
                    state <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    bf_en <= 1'b1;
                    state <= S_CAPTURE;
                end

                S_CAPTURE: begin
                    if (bf_out_valid) begin
                        a_result <= bf_a_out;
                        b_result <= bf_b_out;
                        state    <= S_WRITE;
                    end
                    // else: stay (defensive -- normally valid the very next cycle)
                end

                S_WRITE: begin
                    we_pulse <= 1'b1;
                    state    <= S_ADV;
                end

                S_ADV: begin
                    if (last_bf_latched) begin
                        state <= S_DONE;
                    end else begin
                        ag_adv <= 1'b1;
                        state  <= S_ADVWAIT;
                    end
                end

                S_ADVWAIT: begin
                    // one bubble cycle: ag_adv (asserted last state, registered)
                    // is presented to addr_gen THIS cycle; addr_gen's counters
                    // (and new_group) land at the end of this cycle, so it is
                    // only safe to sample zeta_valid starting next cycle.
                    state <= S_GWAIT;
                end

                S_DONE: begin
                    o_busy <= 1'b0;
                    o_done <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
