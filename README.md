# Parameterized NTT Accelerator for ML-KEM (Verilog / AMD Vivado)

A radix-2 Number Theoretic Transform (NTT) accelerator implementing the
actual **ML-KEM / Kyber "incomplete NTT"** construction defined in
[FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) — not a generic
textbook NTT. It's built to be re-parameterized to any power-of-two
ring degree `N` (as long as the prime `Q` has a primitive `N`-th root of
unity), and is verified bit-exact against a Python golden model,
including the real ML-KEM parameters (`N=256`, `Q=3329`).

## Why "incomplete" NTT?

A full negacyclic NTT over `Z_q[X]/(X^N+1)` needs a primitive `2N`-th
root of unity mod `q`. For ML-KEM's `q = 3329`, `q-1 = 3328 = 2^8 * 13`,
which is **not** divisible by `2*256 = 512`. So a full 256-point
transform doesn't exist mod 3329 — this is exactly why the real ML-KEM
spec stops the NTT one stage early (at butterfly length 2 instead of 1),
leaving `N/2` irreducible degree-2 polynomial factors instead of `N`
fully-split roots. This design implements that same construction
generically for any `N`, and reproduces FIPS 203's published zeta table
exactly when instantiated with the standard `N=256, Q=3329` (ζ₁ = 1729,
matching the spec).

## Architecture

```
                 ┌─────────────┐
   i_start ─────▶│             │
                 │  ntt_fsm    │◀── addr_gen (stage/group/butterfly
   o_busy  ◀─────│ (controller)│      address + zeta-index walker)
   o_done  ◀─────│             │◀── zeta_sched (fetch-once-per-group
                 └──────┬──────┘      cache in front of zeta_rom)
                        │
                        ▼
                 ┌─────────────┐        ┌───────────┐
   ext_we/addr/ ─▶│  coeff_mem  │◀──────▶│butterfly_pe│
   wdata/rdata    │ (dual-port) │        │ t=ζ·b mod q│
                 └─────────────┘        │ a±t mod q  │
                                         └───────────┘
```

- **`addr_gen`** walks the iteration space of the Kyber NTT loop
  (`for len = N/2 downto 2: for each group: for each j in group`),
  producing `(addr_a, addr_b, zeta_idx)` and boundary strobes
  (`new_group`, `last_bf`) each butterfly.
- **`zeta_sched`** fetches a fresh twiddle factor from `zeta_rom` only
  when `new_group` fires, holds it for the whole group (all butterflies
  in a group share one zeta — matching the ML-KEM spec exactly), and
  exposes a clean valid handshake so the FSM never has to hardcode ROM
  latency.
- **`butterfly_pe`** computes `t = ζ·b mod Q`, `a_out = a+t mod Q`,
  `b_out = a-t mod Q`, pipelined to match `mod_mult`'s 1-cycle latency.
- **`coeff_mem`** is a true dual-port RAM holding all `N` coefficients
  in place; the FSM uses both ports simultaneously per butterfly.
- **`ntt_fsm`** is a straightforward, non-overlapped controller: each
  butterfly goes through read → multiply → add/sub → write → advance
  before the next one starts. Prioritizes clarity/correctness; see
  "Optimization notes" below for how to pipeline across butterflies.

## Repo layout

```
rtl/         Synthesizable Verilog (parameterized, Vivado-targeted)
tb/          Self-checking Icarus Verilog testbench
scripts/     gen_zetas.py -- Python golden model + zeta/test-vector generator
mem/         Generated $readmemh files (zetas / input / golden output)
waveforms/   VCD waveform dumps from the test runs + a GTKWave save file
sim/         Build output (compiled vvp binaries) -- gitignored except
             for the folder itself
Makefile     `make sim` / `make wave` convenience targets
```

## Running the simulation (Icarus Verilog)

```bash
# 1. Generate zeta table + a random known-answer test vector for a given N
python3 scripts/gen_zetas.py --N 256 --Q 3329 --outdir mem
#   (for N=256, Q=3329 this automatically uses FIPS 203's ζ=17)

# 2. Compile + run the self-checking testbench
iverilog -g2012 -o sim/ntt_tb \
  -DTB_N=256 -DTB_ZFILE='"mem/zetas_N256.mem"' \
  -DTB_INFILE='"mem/input_N256.mem"' -DTB_GOLDFILE='"mem/golden_N256.mem"' \
  rtl/mod_add.v rtl/mod_sub.v rtl/mod_mult.v rtl/butterfly_pe.v \
  rtl/coeff_mem.v rtl/zeta_rom.v rtl/zeta_sched.v rtl/addr_gen.v \
  rtl/ntt_fsm.v rtl/ntt_top.v tb/ntt_tb.v
vvp sim/ntt_tb
# -> PASS: all 256 coefficients match golden model (N=256, Q=3329)
```

Or more simply, using the included Makefile:

```bash
make sim N=256     # generate vectors (if needed) + run the self-check
make wave N=256    # same, plus write waveforms/ntt_sim_N256.vcd
```

Verified passing for N = 4, 8, 16, 32, 64, 128, and 256 (the real
ML-KEM size), each checked bit-exact against the Python reference model
across multiple random input vectors.

## Waveforms

`waveforms/` ships pre-generated VCD dumps from two runs:

- `ntt_sim_N16.vcd` — small transform (N=16), easy to scroll through
  cycle-by-cycle and see the full read → multiply → add/sub → write →
  advance sequence for every butterfly across all stages.
- `ntt_sim_N256.vcd` — the real ML-KEM-sized transform (N=256), useful
  to confirm timing/behavior at the actual target size.

Open either with [GTKWave](http://gtkwave.sourceforge.net/):

```bash
gtkwave waveforms/ntt_sim_N16.vcd waveforms/ntt_sim.gtkw
```

The `.gtkw` save file pre-loads a useful signal set: clock/reset/start/
busy/done, the FSM state, the address generator's `addr_a`/`addr_b`/
`zeta_idx`, the zeta scheduler's `new_group`/`zeta_valid`/`zeta_cur`
handshake, the butterfly PE's `en`/`out_valid`, and the memory
read/write data — enough to trace one full butterfly end-to-end.

To regenerate (e.g. for a different N), use `make wave N=<size>`.

## Using `ntt_top` in a larger design

```verilog
ntt_top #(
    .N (256), .Q (3329), .W (12), .AW (8), .ZAW (7),
    .INITFILE ("zetas_N256.mem")
) u_ntt (
    .clk (clk), .rst_n (rst_n),
    .i_start (start), .o_busy (busy), .o_done (done),
    .ext_we (we), .ext_addr (addr), .ext_wdata (wdata), .ext_rdata (rdata)
);
```

1. With `busy == 0`, write all `N` input coefficients one per cycle via
   `(ext_we, ext_addr, ext_wdata)`.
2. Pulse `i_start` for one cycle.
3. Wait for the single-cycle `o_done` pulse.
4. With `busy == 0`, read back the `N` transformed coefficients via
   `(ext_addr, ext_rdata)` (1-cycle read latency).

To retarget a different `N`/`Q`: regenerate the zeta file with
`gen_zetas.py`, re-point `INITFILE` at it, and pass matching `N`, `AW =
$clog2(N)`, `ZAW = $clog2(N/2)` parameters. `Q` must be prime and
`(Q-1)` must be divisible by `N`.

## Optimization notes (for a production Vivado flow)

This implementation favors clarity and a verified-correct baseline over
maximum Fmax/throughput. Straightforward next steps if you're taking
this further:

- **Barrett or Montgomery reduction** — `mod_mult` currently uses
  behavioral `%` against a constant `Q`; Vivado constant-folds this into
  a combinational reduction network, but a hand-built Barrett/Montgomery
  reducer will generally synthesize smaller and faster. The module's
  port list is unchanged, so it's a drop-in replacement.
- **Butterfly pipelining / overlap** — `ntt_fsm` currently completes one
  butterfly fully (read → compute → write) before starting the next.
  Since all butterflies within a stage touch disjoint memory addresses,
  successive butterflies could be overlapped (start the next read while
  the current one is still in the multiply/write stages) for a large
  throughput gain, at the cost of a deeper/more state in the FSM.
- **Multi-lane butterflies** — with wider dual-/quad-port memory,
  multiple butterfly PEs could run in parallel within a group (they're
  independent), trading memory ports for throughput.
- **BRAM inference** — `coeff_mem` and `zeta_rom` are written in a
  standard inferable block-RAM style for Vivado; check the synthesis
  report to confirm they map to BRAM rather than distributed RAM at
  your target `N`.
