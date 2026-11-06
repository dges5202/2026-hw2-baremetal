---
tags: computer-arch
---

# Assignment 2 — Quiz 3 C: bitwise adders and Q11.20 `q_mul`
> contributed by [dges5202](https://github.com/dges5202)

NCKU CSIE Computer Architecture, Fall 2026. Sister notes: [binary GCD](../../03-gcd/notes/hackmd.md), [BFloat16](../../02-bf16/notes/bench.md). Sources live in the fork of [`arch2026-progs`](https://github.com/sysprog21/arch2026-progs): `src/fixed/fixed.c` and `src/fixed/fixed.S`. Pin commit links after the first push of this tree.

## Environment

| Item | Value |
| :--- | :--- |
| Harness | `arch2026-progs` (`make` / `scripts/driver.py --prog fixed`) |
| Toolchain | `riscv64-unknown-elf-gcc` 16.x, `-march=rv32i_zicsr -mabi=ilp32` |
| Emulator | [rv32emu](https://github.com/sysprog21/rv32emu) system emulation + `ELF_LOADER` |
| Host check | `make build/host/fixed && ./build/host/fixed` (ASan + UBSan) |

rv32emu has no timing model: `cycle` and `instret` both count executed guest instructions. CPI after subtracting the counter window is 1. A taken branch costs the same as a fall-through; the only way to win is to **retire fewer instructions**.

Reproduce:

```bash
make build/host/fixed && ./build/host/fixed
make build/fixed/O2/fixed.elf
third_party/rv32emu/build/rv32emu build/fixed/O2/fixed.elf
scripts/driver.py --prog fixed
```

---

# Principle

Quiz 3 Problem C asks for four routines. The first three build addition-family ops from bitwise logic; the fourth is a Q11.20 fixed-point multiply. The contract is `src/fixed/fixed.h`. Gate-delay and sequential-circuit parts of the quiz are not programs and are not ported.

## `op1` — carry-loop adder

One bit of addition is

$$
\begin{aligned}
\mathrm{sum} &= a \oplus b \\
\mathrm{carry} &= (a \land b) \ll 1
\end{aligned}
$$

Applied to whole words, each pass replaces $(a,b)$ with $(\mathrm{sum},\mathrm{carry})$ until the carry word is zero. The return value is $a+b \bmod 2^{32}$; `*n` is the number of passes. `op1(x,0)` returns $x$ with `*n = 0`. `op1(0xFFFF,1)` returns `0x10000` with `*n = 17` because the carry walks from bit 0 to bit 16. The longest case is 32 passes (`0xFFFFFFFF + 1`).

The C loop is the algorithm. The assembly uses a bottom-tested form so a continuing iteration is five instructions (`and` / `xor` / `slli` / `addi` / `bnez`) and does not need a `mv` or a top-of-loop `j`.

```c
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    uint32_t c;
    int count = 0;
    while (b != 0) {
        c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count++;
    }
    *n = count;
    return a;
}
```

## `op2` — subtraction

$a - b \bmod 2^{32}$ is the same bit pattern as $a + (\sim b + 1)$. The bitwise model is therefore two calls to `op1`. The instruction budget asks for the plain subtraction: one `sub` is enough, and that is what gcc `-O2` emits from either form of the C.

## `op3` — floor average without overflow

$\lfloor (a+b)/2 \rfloor$ of the exact sum. `(a + b) >> 1` in `uint32_t` overflows when both are large. An equivalent that never wraps is

$$
(a \gg 1) + (b \gg 1) + (a \land b \land 1)
$$

The last term restores the carry that both LSB 1s would have produced. `op3(0xFFFFFFFF, 1) = 0x80000000`.

## `q_mul` — Q11.20 product

A stored `int32_t` $A$ represents the real $A / 2^{20}$. The product is formed in 64 bits, half a unit ($2^{19}$) is added, and the sum is shifted right arithmetically by 20. Ties therefore round toward $+\infty$: `q_mul(3, 524288) = 2`, `q_mul(-3, 524288) = -1`. The low 32 bits of that result are kept; values outside the format wrap.

RV32I has no `mul`. A direct `int64_t` multiply becomes `__muldi3`, which the freestanding runtime does not supply. Both C and assembly therefore:

1. Take absolute values and remember the product sign.
2. Form the unsigned 32×32→64 magnitude (C: four 16×16 partial products through `__mulsi3`; assembly: a branched shift-and-add into a register pair).
3. Negate the 64-bit product when the signs differ.
4. Add `0x80000` with carry into the high word, then return `(lo >> 20) | (hi << 12)`.

Unsigned multiply of the raw two's-complement bit patterns is **not** a signed 32×32→64: the high half differs whenever either operand has bit 31 set. Absolute values first, then unsigned multiply, then conditional negate.

---

# Analysis (rv32emu, `-O2`)

Worst call over the grader's 64×64 grid plus 4096 random pairs (`@@perf`):

| Function | C worst | ASM worst | Budget (ASM / C) |
| :--- | ---: | ---: | ---: |
| `op1` | 169 | 169 | 600 / 1500 |
| `op2` | 6 | 6 | 40 / 150 |
| `op3` | 11 | 11 | 40 / 150 |
| `q_mul` | 519 | 399 | 1200 / 3000 |

Bench window over 16 fixed inputs (`@@bench`, checksums match C ↔ ASM):

| Function | C cycles | ASM cycles | ASM / best C |
| :--- | ---: | ---: | ---: |
| `op1` | 453 | 453 | 1.00× |
| `op2` | 163 | 163 | 1.00× |
| `op3` | 243 | 243 | 1.00× |
| `q_mul` | 5199 | 3613 | 1.45× |

`.text` of the implementation objects: C `-O2` 348 B, hand-written 216 B (`op1` 36 B, `op2` 8 B, `op3` 28 B, `q_mul` 144 B).

---

# Verification

Host: 15 micro-tests (directed / grid / random / laws for `op1`, subtraction and average laws, `q_mul` cases + reference + laws). Guest: the same suite for C and for `_asm`, plus C↔ASM agreement on the benchmark inputs, instruction budgets, and `scripts/driver.py --prog fixed` → **55.0/55**.

---

# Optimization notes

| Change | Why |
| :--- | :--- |
| `op1` bottom-tested loop | Drop per-iteration `mv` and `j`; match gcc's five-insn body. |
| `op2` single `sub` | Same bits as `op1(a, op1(~b,1))`; budget and gcc both want this. |
| `op3` `(a>>1)+(b>>1)+(a&b&1)` | Same instruction count as `-O2`. |
| `q_mul` branched shift-add | Skip the 64-bit add when the multiplier bit is 0; mask form did more work per bit on rv32emu. |
| C `q_mul` via 16×16 | Avoid `__muldi3`; keep host and guest identical. |

`op1`/`op2`/`op3` currently match the best C build (allowed). `q_mul` is the place the hand-written path wins: no call overhead, no spilled temporaries, and an early exit when the remaining multiplier bits are zero.

---

# Real-world angle

Bitwise adders show up in soft-CPU ALUs and in code that must run without an M extension. Q11.20 is the same fixed-point style used in the course's line-drawing note: integer multiply, a rounding bias, and an arithmetic shift back into the format, with wrap instead of saturation when the product overflows the 32-bit store.
