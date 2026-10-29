---
tags: computer-arch
---

# Assignment 2: Complete Applications on Bare-Metal RV32I
> contributed by [dges5202](https://github.com/dges5202)

NCKU CSIE Computer Architecture, Fall 2026. This note follows [Assignment 2](https://hackmd.io/@sysprog/2026-arch-homework2). Listings are short excerpts pinned to GitHub commits; the full sources live in the [repository](https://github.com/dges5202/2026-hw2-baremetal).

The four programs are minirubik, BFloat16, binary GCD, and the Quiz 3 logic / `q_mul` pair. This draft covers **binary GCD**. The other three, the gcc comparison, and the bare-metal micro-test port are still open.

## Environment

| Item | Value |
| :--- | :--- |
| Repository | https://github.com/dges5202/2026-hw2-baremetal |
| Host | AMD Ryzen 7 9800X3D, Linux 6.6 (WSL2) |
| Toolchain | `riscv64-unknown-elf-gcc` 16.1.0, `-march=rv32i_zicsr -mabi=ilp32` |
| Emulator | [rv32emu](https://github.com/sysprog21/rv32emu) `cab9a11`, `system_defconfig` + `CONFIG_ELF_LOADER=y` |
| Guest syscalls | `write` (64) and `exit` (93) only |

Homework 1 measured retired instructions on Ripes `RV32_ISS` and cycles on `RV32_5S`, so CPI recorded stalls and flushes. **rv32emu has no timing model:** `cycle` and `instret` both count executed guest instructions. After subtracting the counter-read window they are equal, and CPI on this emulator is 1. A taken `j` costs the same as a fall-through. The only way fall-through wins here is to **delete the jump instruction** from the executed path. Load-use hazards and branch flushes do not appear in these numbers. Code size is weighed separately with `size -A`.

The timed region around `gcd` is always

```
get_cycles; get_instret;  <body>;  get_instret; get_cycles
```

An empty body (the probe) retires **21 cycles / 7 instret**. Each Quiz pair includes that probe plus `mv` / `jal gcd` / `mv`. **Gcd-only retired** is `iret − 7` per pair, which is also `cyc − 21`. Print, `_start`, and the CSR helpers sit outside that number. An optimization counts only if the six Quiz lines still match.

Reproduce:

```bash
source env.sh
make -C 03-gcd test      # host C, 12 cases
make -C 03-gcd run-asm   # guest ELF on rv32emu
riscv64-unknown-elf-size -A 03-gcd/gcd.elf
```

---

# Binary GCD (Quiz 2 A)

Stein’s algorithm (the binary GCD) replaces Euclid’s division with shifts and subtractions. Quiz 2 already ran it on Ripes with print-integer syscalls. The homework is to run the same six pairs on rv32emu under the RV32I-only rule, print decimal without `div`/`rem`, and then cut the instruction count of the `gcd` path.

## Principle

For unsigned $a$ and $b$, four identities are enough ([Quiz 2 solutions](https://hackmd.io/@sysprog/arch2026-quiz2-sol)):

$$
\begin{aligned}
\gcd(0, b) &= b \\
\gcd(2a, 2b) &= 2 \cdot \gcd(a, b) \\
\gcd(2a, b) &= \gcd(a, b) \quad \text{when } b \text{ is odd} \\
\gcd(a, b) &= \gcd(a, b - a) \quad \text{when } a, b \text{ are both odd and } b \ge a
\end{aligned}
$$

The implementation applies them in that order.

1. If either side is zero, return the other (identity 1). $\gcd(0,0)$ is defined here as 0.
2. While both are even, shift both right and remember how many twos were shared (identity 2).
3. Shift each side on its own until it is odd (identity 3).
4. While the odd values differ, subtract the smaller from the larger. The difference of two odds is even, so one more right shift is free (identities 4 and 3). Stop when they are equal; that odd value is $\gcd$ with the shared twos removed.
5. Shift the odd gcd left by the shared count.

The C version on the host is the spec I assembled against. The `% 2` tests become `andi` on the guest; the rest is the same control flow.

```c
/* https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.c#L12-L40 */
unsigned gcd(unsigned a, unsigned b)
{
    unsigned count = 0;
    if (a == 0) return b;
    if (b == 0) return a;
    while (a % 2 == 0 && b % 2 == 0) {
        a >>= 1; b >>= 1; count++;
    }
    while (a != b) {
        while ((a & 1) == 0) a >>= 1;
        while ((b & 1) == 0) b >>= 1;
        if (a > b) a = (a - b) >> 1;
        else if (a < b) b = (b - a) >> 1;
        else break;
    }
    return a << count;
}
```

Why the identities hold, briefly:

- Every integer divides 0, so the common divisors of $0$ and $b$ are exactly the divisors of $b$.
- A factor of two that both sides share can be pulled out of the gcd. After that, identity 3 says a two that only one side still has is not common, so it can be discarded.
- Euclid’s step $\gcd(a,b)=\gcd(a,b-a)$ does not need a remainder. When both values are odd, $b-a$ is even, and identity 3 lets us drop that two immediately: $\gcd(a,b)=\gcd(a,(b-a)/2)$.

The 2-adic valuation makes the shared-two count a one-liner. For $n \ne 0$, $v_2(n)$ is the trailing-zero count. Then

$$
v_2(\gcd(a,b)) = \min(v_2(a), v_2(b)) = v_2(a \lor b)
$$

so the number of times identity 2 fires is $\mathrm{ctz}(a \lor b)$, not $\mathrm{ctz}(a \land b)$. Using AND would stop one bit too early whenever the lowest set bits of $a$ and $b$ sit at different positions.

## Mathematical foundation and the RV32I number format

The domain is the unsigned 32-bit integers $\{0, \dots, 2^{32}-1\}$. There is no rounding: the result is exact, and the error against a host `unsigned` reference is identically zero on every pair that fits in 32 bits.

Three consequences of the format, all forced by the Quiz pairs:

**Bit 31 is data, not a sign.** Pair 3 is $(2^{31}+1, 3) = (0\text{x}80000001, 3)$ and pair 2 is $(0\text{xF0000000}, 0\text{x}30000000)$. A signed `blt` / `bge` would treat $0\text{x}80000001$ as negative and take the wrong subtract arm. Every compare is `bltu` / `bgeu` / `beq`.

**Shifts are logical.** After `a - b` both sides were odd, so $a-b$ is even and $(a-b)/2$ is an integer. `srai` would fill ones when bit 31 of the difference is set (pair 2 lives in that range). The code uses `srli` / `srl`.

**The subtract cannot wrap.** The `a > b` arm runs only after `bltu` has established $a > b$, so $a-b$ is the mathematical difference and fits in 32 bits. The same holds with the operands swapped on `larger_b`.

The largest printable result is $2^{32}-1 = 4\,294\,967\,295$, ten decimal digits. `print_u32` therefore subtracts $10^9, \dots, 10^0$ and never needs a digit beyond 9 from $10^9$. Leading zeros are suppressed except for the value 0, which must still print `"0"`.

RV32I has no `ctz` (that is Zbb) and no `div`/`rem`. The shared-two peel is a shift loop, later a binary search over the bit width; decimal conversion is repeated subtraction of a table in `.rodata`. No multiply appears in this program, so `__mulsi3` is not required.

## Analysis: what the six pairs actually exercise

| Pair | Inputs | Result | What it stresses |
| :--- | :--- | ---: | :--- |
| 0 | (1071, 462) | 21 | typical mixed odds, several subtracts |
| 1 | (4096, 3072) | 1024 | both powers of two; almost all work is `even_loop` |
| 2 | $(0\text{xF0000000}, 0\text{x}30000000)$ | $0\text{x}30000000$ | long shared-two run (bit 31 set) |
| 3 | $(0\text{x}80000001, 3)$ | 3 | unsigned `a > b` subtract, many times |
| 4 | (0, 91) | 91 | early return; not a speed target |
| 5 | (6, 10) | 2 | shared $k=1$ only |

Pairs 2 and 3 dominate the sum. Pair 5 is the canary for a binary `even_loop` that walks $16 \to 1$ even when $k=1$. Pair 4 is a smoke check: if it moves, the early return broke.

Baseline, commit [`958ff64`](https://github.com/dges5202/2026-hw2-baremetal/commit/958ff64) (same `gcd` as the first working guest, plus the CSR window):

| Pair | Window cyc / iret | Gcd-only |
| :--- | ---: | ---: |
| (1071, 462) | 86 / 72 | 65 |
| (4096, 3072) | 125 / 111 | 104 |
| (0xF0000000, 0x30000000) | 247 / 233 | 226 |
| (0x80000001, 3) | 229 / 215 | 208 |
| (0, 91) | 28 / 14 | 7 |
| (6, 10) | 63 / 49 | 42 |
| **sum** | 778 / 694 | **652** |
| probe | 21 / 7 | 0 |

The whole ELF at that commit: `.text` 792, `.rodata` 124, `.bss` 24, `gcd` symbol 124 bytes. No `.data`.

## Verification

**Host.** `make test` builds `gcd.c` with the host `cc` and runs twelve cases: the six Quiz pairs, $\gcd(0,0)$, $\gcd(91,0)$, $\gcd(1,1)$, two coprime pairs, and two small composites. Each case is also called swapped. A failure prints both directions.

**Guest.** `make run-asm` must print the six Quiz lines exactly, including the unsigned decimal for pair 2 (`4026531840`, not a hex dump and not a negative). The CSR lines are extra; they are not part of the Quiz contract.

**Independent reference.** The host `unsigned` gcd is the reference. The guest is checked by matching the Quiz oracle, which is the same function on those six pairs. I have not yet ported [micro-test](https://github.com/trmckay/micro-test) to this ELF (`NO_STD`, no POSIX capture, own printer). Until that lands, the host suite plus the six guest lines are the gate, and every row in the optimization table passed both.

A deliberately failing test that `start.S` would pass to `exit` is also still missing; that is part of the micro-test smoke check the spec asks for, not of `gcd` itself.

## Optimization

Every row is gcd-only retired over the six pairs, CPI 1.00 on rv32emu, same six printed lines. The full per-pair windows are in [`03-gcd/notes/bench.md`](https://github.com/dges5202/2026-hw2-baremetal/blob/54024ba/03-gcd/notes/bench.md).

| Commit | Change | Retired | `.text` | `gcd` B | Δ |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [`958ff64`](https://github.com/dges5202/2026-hw2-baremetal/commit/958ff64) | CSR baseline | 652 | 792 | 124 | — |
| [`e7c4534`](https://github.com/dges5202/2026-hw2-baremetal/commit/e7c4534) | `even_loop` bottom-tested | 613 | 800 | 132 | −39 |
| [`2b46ee8`](https://github.com/dges5202/2026-hw2-baremetal/commit/2b46ee8) | `strip_*` bottom-tested | 593 | 808 | 140 | −20 |
| [`d489786`](https://github.com/dges5202/2026-hw2-baremetal/commit/d489786) | `a > b` falls into `gcd_loop` (**kept**) | 578 | 812 | 144 | −15 |
| [`de064c5`](https://github.com/dges5202/2026-hw2-baremetal/commit/de064c5) | `larger_b` falls into `gcd_loop` (not kept) | 592 | 808 | 140 | +14 vs `a>b` |
| [`99e8e2b`](https://github.com/dges5202/2026-hw2-baremetal/commit/99e8e2b) | strip only the side just made even | 546 | 836 | 168 | −32 |
| [`577ecda`](https://github.com/dges5202/2026-hw2-baremetal/commit/577ecda) | `strip_b` falls into `odd_sub` | 544 | 828 | 160 | −2 |
| [`9fe12b6`](https://github.com/dges5202/2026-hw2-baremetal/commit/9fe12b6) | binary 16/8/4/2/1 `even_loop` | 439 | 860 | 192 | −105 |
| [`97c3cba`](https://github.com/dges5202/2026-hw2-baremetal/commit/97c3cba) | nibble split; delay `li t5`/`t6` | 403 | 900 | 232 | −36 |
| [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/commit/9780d53) | drop extra `or` before nibble | 400 | 896 | 228 | −3 |

Net: **652 → 400** gcd-only retired (−39%), `gcd` grew 124 → 228 bytes. The current per-pair gcd-only counts at [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/commit/9780d53) are 53, 73, 65, 163, 7, 39.

### Fall-through loops, not a 5-stage trick

On rv32emu a `j` is one retired instruction, taken or not. The win from a bottom-tested loop is that the hot iteration executes `beq` back to the body and **does not execute a trailing `j`**. The first-working `even_loop` tested at the top and jumped to the body; moving the test to the bottom saved 39 on the sum, almost all of it on pairs 1 and 2, which spend their time shifting.

The same shape on `strip_a` / `strip_b` saved another 20, 14 of them on pair 3, which peels the leftover two on $0\text{x}80000001$ many times.

### Which subtract arm falls into the compare

A 3-block cycle can give a fall-through predecessor to at most two labels. After `odd_sub`, either `a > b` or `a < b` can fall into the next strip; the other arm needs a `j`.

I measured both layouts against [`2b46ee8`](https://github.com/dges5202/2026-hw2-baremetal/commit/2b46ee8). Letting `a > b` fall through ([`d489786`](https://github.com/dges5202/2026-hw2-baremetal/commit/d489786)) saved 15, of which 15 were pair 3. Letting `larger_b` fall through ([`de064c5`](https://github.com/dges5202/2026-hw2-baremetal/commit/de064c5)) saved 1 on the sum and **lost 15 on pair 3**. Pair 3 is the hot `a > b` arm, so that is the layout I kept.

Rotating `odd_sub` itself into a third fall-through would need a duplicated block. I did not pay that size for a layout the 3-block cycle cannot give for free.

### Strip only the side that just became even

After `a = (a - b) >> 1`, $b$ is still odd. Walking `strip_b` on that arm is dead work. First entry still has to peel both sides (`strip_a1` then `strip_b`); after that, `a > b` goes only to `strip_a` and `larger_b` only to `strip_b`.

That is [`99e8e2b`](https://github.com/dges5202/2026-hw2-baremetal/commit/99e8e2b): −32, −16 of them on pair 3. `gcd` grew 144 → 168 because `strip_a1` is a second copy of the peel. Reordering so `strip_a1_inner` falls into `strip_b` and `strip_b_inner` falls into `odd_sub` ([`577ecda`](https://github.com/dges5202/2026-hw2-baremetal/commit/577ecda)) took two more instructions off the first entry. `strip_a_inner` still `j odd_sub` so it cannot fall into `larger_b`.

The current subtract and strip, pinned at [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.S#L266-L318):

```
strip_a1:
    andi    t1, a0, 1
    bne     t1, x0, strip_b
strip_a1_inner:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, strip_a1_inner

gcd_loop:
strip_b:
    andi    t1, a1, 1
    bne     t1, x0, odd_sub
strip_b_inner:
    srli    a1, a1, 1
    andi    t1, a1, 1
    beq     t1, x0, strip_b_inner          # then fall into odd_sub

odd_sub:
    beq     a0, a1, gcd_done
    bltu    a0, a1, larger_b
    sub     a0, a0, a1
    srli    a0, a0, 1                      # fall into strip_a
strip_a:
    andi    t1, a0, 1
    bne     t1, x0, odd_sub
strip_a_inner:
    srli    a0, a0, 1
    andi    t1, a0, 1
    beq     t1, x0, strip_a_inner
    j       odd_sub
larger_b:
    sub     a1, a1, a0
    srli    a1, a1, 1
    j       strip_b
```

### Shared twos: 1-bit, then binary, then a nibble split

A 1-bit `even_loop` is the Quiz shape. Pair 2 shares many twos ($v_2(0\text{xF0000000})=28$), so a 1-bit peel is linear in $k$. RV32I has no `ctz`, so I count trailing zeros of $a \lor b$ with a 16/8/4/2/1 walk: if the low $k$ bits of $a \lor b$ are zero, shift both by $k$ and add $k$ to the count, then halve $k$.

That is [`9fe12b6`](https://github.com/dges5202/2026-hw2-baremetal/commit/9fe12b6): −105 on the sum, −132 on pair 2 — and **+40 on pair 5**. $(6,10)$ shares one two. The binary walk still tests 16, 8, 4, 2, and 1. Odd pairs also paid `li t5` / `li t6` even when they skipped the inner loop; `li t6, 0xFFFF` is `lui`+`addi`, not one instruction.

The nibble split ([`97c3cba`](https://github.com/dges5202/2026-hw2-baremetal/commit/97c3cba)) is the layout I kept. After the parity test, $(a \lor b) \land 0\text{xF}$:

- nonzero means $k \in \{1,2,3\}$: keep the 1-bit peel (`even_loop_shortcut`);
- zero means $k \ge 4$: take the binary walk (`even_loop_skip`).

`t5`/`t6` are loaded only on the binary path. Pair 5 drops from 76 back to 40. Pair 2 pays three extra instructions for the nibble test and still uses binary. Sum 439 → 403. Dropping a redundant `or` (`t1` already holds $a \lor b$ after the parity `andi`) is [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/commit/9780d53), another −3.

```
# https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.S#L225-L264
even_loop:
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, strip_a1
    andi    t2, t1, 0xF
    beq     t2, x0, even_loop_skip
even_loop_shortcut:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t2, t1, 1
    beq     t2, x0, even_loop_shortcut
    j       strip_a1
even_loop_skip:
    li      t5, 16
    li      t6, 0xFFFF
even_loop_inner:
    or      t1, a0, a1
    and     t2, t1, t6
    bne     t2, x0, even_loop_inner1
    srl     a0, a0, t5
    srl     a1, a1, t5
    add     t0, t0, t5
even_loop_inner1:
    srli    t5, t5, 1
    srl     t6, t6, t5
    or      t1, a0, a1
    andi    t2, t1, 1
    beq     t2, x0, even_loop_inner
```

A forced “do one 1-bit step, then always enter binary” (the other split I tried) lost on pair 2: $k=28$ still walked 16/8/4/2/1 after paying the extra step, and the sum was worse by one. I did not keep it.

### What I measured and did not keep

- **Dual-path state machine** that special-cases $a>b$ at entry. On this suite the extra prologue is not paid back; pair 3 is already the fall-through arm.
- **Binary `strip_*`.** After `odd_sub` the leftover twos on one side are usually 1. A 16/8/4/2/1 walk loses on that common case; a 14-iteration extra=$1$ loop is cheaper as 1-bit.
- **`sltu` min/max** instead of `bltu` + two arms. It does not remove work from the hot subtract; it only reshapes it. I will look at it again when I have a gcc listing to beat, not before.
- **Load-use / 5-stage scheduling.** Invisible on rv32emu. Reordering for a forwarding slot would be fiction in these counters.

## RV32I improvements, and what they cost

The Quiz listing was already RV32I. What the homework actually took away was the Ripes print-integer syscall (a7 = 36) and the divider it was allowed to pretend existed. `print_u32` is a leaf: for each power in `pow10[]` it counts how many times the power fits by unsigned subtract, then `write`s one ASCII byte. It does not touch the saved registers `main` keeps across `jal gcd`, and it does not use the stack.

```
# https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.S#L327-L364
print_u32:
    mv      s5, a0
    la      s6, pow10
    li      s7, 10
    mv      s8, x0
pu_pow:
    beq     s7, x0, pu_done
    lw      t1, 0(s6)
    li      t0, 0
pu_sub:
    bltu    s5, t1, pu_emit
    sub     s5, s5, t1
    addi    t0, t0, 1
    j       pu_sub
pu_emit:
    ...
    addi    t0, t0, 48
    la      a1, buf
    sb      t0, 0(a1)
    li      a2, 1
    li      a0, 1
    li      a7, 64
    ecall
```

Startup is the playground pattern: set `sp`, zero `.bss`, `call main`, `exit`. Zicsr is used only in `perfcounter.S` to read `cycle`/`instret` with the high-low-high retry. Application `gcd` never touches a CSR.

The remaining RV32I cost inside `gcd` is the missing `ctz`. A de Bruijn table would replace the nibble/binary peel with a multiply, which this ISA also does not have, or with a 32-entry load — a load that is not cheaper than the nibble test on $k \le 3$, which is the common Quiz case. The nibble split is the RV32I answer I am willing to defend on this suite.

I have not yet disassembled gcc `-O2`/`-O3`/`-Os` of the C `gcd` on the same window. The spec wants handwritten cycles against the fastest gcc and handwritten size against the smallest gcc. That table is the next measurement, not a claim I can make today.

## Real-world applications

Binary GCD is the algorithm GMP and several cryptographic libraries use when a fast divider is missing or when the inputs are even more often than not. RSA, modular inverses, and fraction reduction all start from $\gcd$. The constraints carry over directly: the inputs are unsigned, bit 31 is not a sign, and every two you can see should be shifted off before you subtract. A hardware `ctz` (Zbb / BMI) collapses `even_loop` to one instruction; the nibble split is what the same idea looks like when the core is RV32I.

The six Quiz pairs are not a cryptographic workload. They are a bias: two long-shift cases, one long unsigned subtract, one $k=1$ canary. An optimization that wins on pair 2 and loses on pair 5 is visible here, which is the point of keeping all six in the sum.

## Still open on this program

- Port micro-test (`NO_STD`, own printer, no POSIX capture) and put the twelve host cases, plus the six guest lines, behind `register_test()`.
- Same CSR window on gcc `-O0`/`-O2`/`-O3`/`-Os`; compare cycles to the fastest and `.text` of `gcd` to the smallest.
- Revisit `sltu` only if the gcc listing still has a swap that the handwritten code can delete.

---

The other three programs of Assignment 2 will follow in this note as they land.
