#!/usr/bin/env python3
"""
Golden-model generator for the parameterized NTT accelerator.

Implements the Kyber/ML-KEM-style NTT loop:

    k = 1
    for len in N/2, N/4, ..., 1:
        for start = 0; start < N; start += 2*len:
            zeta = zetas[k]; k += 1
            for j in start .. start+len-1:
                t = zeta * a[j+len] mod q
                a[j+len] = a[j] - t mod q
                a[j]     = a[j] + t mod q

zetas[i] = psi^BitRev(i, logN) mod q, where psi is a primitive 2N-th root
of unity mod q (so psi^2 is a primitive N-th root of unity), matching the
ring Z_q[X]/(X^N + 1).

This script:
  1. Finds a primitive 2N-th root of unity mod q.
  2. Emits the zeta ROM contents (zetas[1..N-1], zeros elsewhere) as hex.
  3. Runs the golden NTT on a random input vector.
  4. Emits input/output vectors as hex memory files for the testbench,
     plus stage-by-stage trace info used to sanity check the RTL's
     addressing scheme (zeta index = 2^s + g).
"""
import argparse
import random


def find_primitive_root(q):
    """Find a primitive root of the multiplicative group mod q (q prime)."""
    phi = q - 1
    # factor phi
    factors = set()
    n = phi
    d = 2
    while d * d <= n:
        while n % d == 0:
            factors.add(d)
            n //= d
        d += 1
    if n > 1:
        factors.add(n)
    for g in range(2, q):
        if all(pow(g, phi // p, q) != 1 for p in factors):
            return g
    raise RuntimeError("no primitive root found")


def find_primitive_n_root(q, N):
    """Find g such that g has multiplicative order exactly N mod q. This is
    the FIPS 203 / ML-KEM construction: the ring Z_q[X]/(X^N+1) is only
    *incompletely* split by an N-th root of unity (q=3329, N=256 does NOT
    have a primitive 2N-th root -- 3328 is not divisible by 512 -- which is
    exactly why the real NTT stops one stage early, at length=2, leaving
    N/2 irreducible degree-2 factors)."""
    assert (q - 1) % N == 0, f"q-1 must be divisible by N (q={q}, N={N})"
    g0 = find_primitive_root(q)
    g = pow(g0, (q - 1) // N, q)
    assert pow(g, N, q) == 1
    # verify order is exactly N (not a proper divisor)
    for p in {2}:
        pass
    order = N
    n = N
    d = 2
    while d * d <= n:
        while n % d == 0:
            if pow(g, order // d, q) == 1:
                order //= d
            n //= d
        d += 1
    if n > 1 and pow(g, order // n, q) == 1:
        order //= n
    assert order == N, f"g has order {order}, expected {N}"
    return g


def bitrev(x, bits):
    r = 0
    for i in range(bits):
        r = (r << 1) | (x & 1)
        x >>= 1
    return r


def gen_zetas(q, N, root=None):
    """Incomplete NTT (ML-KEM style): logn-1 stages, length from N/2 down to
    2. zetas[] has N/2 entries (index 0 unused), zetas[i] = g^BitRev(i, logn-1)
    for i = 1 .. N/2-1, where g is a primitive N-th root of unity.
    For the standard ML-KEM parameters (q=3329, N=256), FIPS 203 fixes
    g = 17; pass root=17 to reproduce the exact standard zeta table."""
    logn = N.bit_length() - 1
    assert (1 << logn) == N, "N must be a power of two"
    assert logn >= 2, "N must be >= 4 for the incomplete NTT (need at least one stage)"
    if root is not None:
        assert pow(root, N, q) == 1, "supplied root does not have order dividing N"
        g = root
    else:
        g = find_primitive_n_root(q, N)
    revbits = logn - 1
    zetas = [0] * (N // 2)
    for i in range(1, N // 2):
        zetas[i] = pow(g, bitrev(i, revbits), q)
    return zetas, g


def ntt(a, zetas, q, N):
    """Incomplete NTT: stages for length = N/2, N/4, ..., 2 (stops before
    length=1). Output is N/2 pairs of coefficients, each pair an
    irreducible degree-1... really degree-2 factor's coefficient pair."""
    a = a[:]
    k = 1
    length = N // 2
    while length >= 2:
        start = 0
        while start < N:
            zeta = zetas[k]
            k += 1
            for j in range(start, start + length):
                t = (zeta * a[j + length]) % q
                a[j + length] = (a[j] - t) % q
                a[j] = (a[j] + t) % q
            start += 2 * length
        length //= 2
    return a


def zeta_index_schedule(N):
    """Returns list of (stage, group, zeta_index) in the exact order the
    RTL address generator should produce them, using zeta_idx = 2^s + g,
    for stages s = 0 .. logN-2 (logN-1 stages total, stopping before the
    length=1 stage)."""
    logn = N.bit_length() - 1
    sched = []
    for s in range(logn - 1):
        num_groups = 1 << s
        for g in range(num_groups):
            sched.append((s, g, (1 << s) + g))
    return sched


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--N", type=int, default=256)
    ap.add_argument("--Q", type=int, default=3329)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--outdir", type=str, default=".")
    ap.add_argument("--root", type=int, default=None,
                     help="Fix the primitive N-th root (e.g. 17 for standard ML-KEM N=256,Q=3329)")
    args = ap.parse_args()

    N, Q = args.N, args.Q
    root = args.root
    if root is None and N == 256 and Q == 3329:
        root = 17  # FIPS 203 standard value
    zetas, psi = gen_zetas(Q, N, root=root)

    # sanity check the zeta-index schedule matches array we built
    sched = zeta_index_schedule(N)
    max_k = max(k for _, _, k in sched)
    assert max_k == N // 2 - 1, (max_k, N // 2 - 1)

    random.seed(args.seed)
    a_in = [random.randrange(0, Q) for _ in range(N)]
    a_out = ntt(a_in, zetas, Q, N)

    w = (Q - 1).bit_length()
    hexw = (w + 3) // 4

    def wr(fname, vals):
        with open(fname, "w") as f:
            for v in vals:
                f.write(f"{v:0{hexw}x}\n")

    import os
    os.makedirs(args.outdir, exist_ok=True)
    wr(os.path.join(args.outdir, f"zetas_N{N}.mem"), zetas)
    wr(os.path.join(args.outdir, f"input_N{N}.mem"), a_in)
    wr(os.path.join(args.outdir, f"golden_N{N}.mem"), a_out)

    print(f"N={N} Q={Q} g(primitive N-th root)={psi}")
    print(f"logN-1={N.bit_length()-2} stages, {len(sched)} total butterfly groups, "
          f"zeta indices span 1..{max_k}")
    print(f"Wrote zetas_N{N}.mem, input_N{N}.mem, golden_N{N}.mem in {args.outdir}")


if __name__ == "__main__":
    main()
