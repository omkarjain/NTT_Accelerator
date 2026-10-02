// ---------------------------------------------------------------------
// ntt_pkg.vh
// Shared parameters for the parameterized NTT accelerator.
// Included (`include) by modules that need default values; every module
// also exposes its own parameters so the whole design can be
// re-parameterized purely via Verilog parameter overrides (no need to
// edit this file for a new N/Q, as long as Q is prime and N | (Q-1)).
// ---------------------------------------------------------------------
`ifndef NTT_PKG_VH
`define NTT_PKG_VH

`define NTT_DEFAULT_N   256     // ML-KEM ring degree
`define NTT_DEFAULT_Q   3329    // ML-KEM prime modulus
`define NTT_DEFAULT_CW  12      // ceil(log2(Q)) coefficient width

`endif
