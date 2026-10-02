# Requires: Icarus Verilog (iverilog/vvp) and Python 3.
# Usage:
#   make sim N=256          # generate vectors (if missing), run self-check
#   make wave N=256          # same, plus dump waveforms/ntt_sim_N<N>.vcd
#   make clean

N ?= 256
Q ?= 3329

RTL = rtl/mod_add.v rtl/mod_sub.v rtl/mod_mult.v rtl/butterfly_pe.v \
      rtl/coeff_mem.v rtl/zeta_rom.v rtl/zeta_sched.v rtl/addr_gen.v \
      rtl/ntt_fsm.v rtl/ntt_top.v

ZFILE = mem/zetas_N$(N).mem
IFILE = mem/input_N$(N).mem
GFILE = mem/golden_N$(N).mem

.PHONY: sim wave vectors clean

vectors:
	@test -f $(ZFILE) || python3 scripts/gen_zetas.py --N $(N) --Q $(Q) --outdir mem

sim: vectors
	iverilog -g2012 -o sim/ntt_tb_n$(N) \
	  -DTB_N=$(N) -DTB_ZFILE='"$(ZFILE)"' -DTB_INFILE='"$(IFILE)"' -DTB_GOLDFILE='"$(GFILE)"' \
	  $(RTL) tb/ntt_tb.v
	vvp sim/ntt_tb_n$(N)

wave: vectors
	mkdir -p waveforms
	iverilog -g2012 -o sim/ntt_tb_n$(N) \
	  -DTB_N=$(N) -DTB_ZFILE='"$(ZFILE)"' -DTB_INFILE='"$(IFILE)"' -DTB_GOLDFILE='"$(GFILE)"' \
	  -DTB_DUMP='"waveforms/ntt_sim_N$(N).vcd"' \
	  $(RTL) tb/ntt_tb.v
	vvp sim/ntt_tb_n$(N)
	@echo "Waveform written to waveforms/ntt_sim_N$(N).vcd -- open with:"
	@echo "  gtkwave waveforms/ntt_sim_N$(N).vcd waveforms/ntt_sim.gtkw"

clean:
	rm -f sim/ntt_tb_n*
