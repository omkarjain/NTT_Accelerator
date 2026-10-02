// ---------------------------------------------------------------------
// ntt_tb: self-checking testbench.
//   - Loads mem/input_N<N>.mem into the accelerator.
//   - Runs the transform.
//   - Compares the in-place result against mem/golden_N<N>.mem,
//     produced by scripts/gen_zetas.py's Python reference model.
//
// Override N/Q/ZETAFILE/INFILE/GOLDFILE via `+define+` or edit the
// localparams below to test a different size.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module ntt_tb;
    localparam integer N   = `TB_N;
    localparam integer Q   = 3329;
    localparam integer W   = 12;
    localparam integer AW  = $clog2(N);
    localparam integer ZAW = $clog2(N/2);

    reg clk = 0;
    always #5 clk = ~clk;

    reg  rst_n;
    reg  i_start;
    wire o_busy, o_done;

    reg            ext_we;
    reg  [AW-1:0]  ext_addr;
    reg  [W-1:0]   ext_wdata;
    wire [W-1:0]   ext_rdata;

    ntt_top #(
        .N (N), .Q (Q), .W (W), .AW (AW), .ZAW (ZAW),
        .INITFILE (`TB_ZFILE)
    ) dut (
        .clk (clk), .rst_n (rst_n),
        .i_start (i_start), .o_busy (o_busy), .o_done (o_done),
        .ext_we (ext_we), .ext_addr (ext_addr), .ext_wdata (ext_wdata), .ext_rdata (ext_rdata)
    );

    reg [W-1:0] golden [0:N-1];
    reg [W-1:0] input_v [0:N-1];
    integer i;
    integer errors;

    // Waveform dump: compile with -DTB_DUMP='"waveforms/ntt_sim.vcd"' to
    // enable (off by default so plain correctness runs stay fast/small).
    initial begin
`ifdef TB_DUMP
        $dumpfile(`TB_DUMP);
        $dumpvars(0, ntt_tb);
`endif
    end

    initial begin
        $readmemh(`TB_INFILE,   input_v);
        $readmemh(`TB_GOLDFILE, golden);

        rst_n   = 0;
        i_start = 0;
        ext_we  = 0;
        ext_addr = 0;
        ext_wdata = 0;
        errors = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // ---- load input coefficients ----
        for (i = 0; i < N; i = i + 1) begin
            @(posedge clk);
            ext_we    = 1;
            ext_addr  = i[AW-1:0];
            ext_wdata = input_v[i];
        end
        @(posedge clk);
        ext_we = 0;

        // ---- run ----
        @(posedge clk);
        i_start = 1;
        @(posedge clk);
        i_start = 0;

        wait (o_done == 1'b1);
        @(posedge clk); // let o_done pulse pass, busy drop
        @(posedge clk);

        // ---- unload & check ----
        for (i = 0; i < N; i = i + 1) begin
            ext_addr = i[AW-1:0];
            @(posedge clk);
            #1;
            if (ext_rdata !== golden[i]) begin
                errors = errors + 1;
                $display("MISMATCH idx=%0d got=%0d (0x%0h) expected=%0d (0x%0h)",
                          i, ext_rdata, ext_rdata, golden[i], golden[i]);
            end
        end

        if (errors == 0)
            $display("PASS: all %0d coefficients match golden model (N=%0d, Q=%0d)", N, N, Q);
        else
            $display("FAIL: %0d / %0d coefficients mismatched", errors, N);

        $finish;
    end

    // safety watchdog
    initial begin
        #200000;
        $display("TIMEOUT: simulation did not finish");
        $finish;
    end
endmodule
