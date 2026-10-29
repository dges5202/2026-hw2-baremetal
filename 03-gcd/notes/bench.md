# GCD bench log

Same layout as Homework 1 stage 5: one row per commit that changes the guest `gcd` path, measured the same way every time.

## How to read the numbers

Homework 1 used Ripes `RV32_ISS` for retired instructions and `RV32_5S` for cycles, so CPI was real (stalls and flushes). **rv32emu has no timing model:** `cycle` and `instret` both count guest instructions, so CPI on this emulator is 1 after you subtract the counter window.

The window around `gcd` is:

```
get_cycles; get_instret;  <body>;  get_instret; get_cycles
```

`probe` is that window with an empty body (21 cycles / 7 instret). Each pair includes the probe plus `mv` / `jal gcd` / `mv`. **Gcd-only retired** below is `iret − 7` per pair (or `cyc − 21`, same value). That is the number to beat.

Reproduce:

```bash
source ../env.sh
make run-asm
riscv64-unknown-elf-size -A gcd.elf
```

`size -A` is the whole ELF (print, `_start`, counters). The `gcd` symbol itself is listed separately so print-path churn does not look like an algorithm win. An optimization counts only if the six Quiz lines still match.

## Log

| Commit | Change | Retired (6 pairs, gcd-only) | Cycles (gcd-only) | CPI | `.text` | `.rodata` | `.bss` | `gcd` bytes |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `8a44795` | first working Stein (`even_loop` / `strip_*` / `odd_sub`); no CSR window | — | — | — | — | — | — | — |
| *this tree* | same `gcd`, CSR window + `print_cycret` (baseline to optimize against) | 652 | 652 | 1.00 | 792 | 124 | 24 | 124 |

Fill the *this tree* hash when this bench commit lands. Append a row for every later commit that changes `gcd` (fall-through, ctz, `sltu`, …). Tooling-only commits stay out, same as Homework 1.

## Baseline per pair (`8a44795` `gcd` + CSR window)

| Pair | Result | Window cyc / iret | Gcd-only |
| :--- | ---: | ---: | ---: |
| (1071, 462) | 21 | 86 / 72 | 65 |
| (4096, 3072) | 1024 | 125 / 111 | 104 |
| (0xF0000000, 0x30000000) | 805306368 | 247 / 233 | 226 |
| (0x80000001, 3) | 3 | 229 / 215 | 208 |
| (0, 91) | 91 | 28 / 14 | 7 |
| (6, 10) | 2 | 63 / 49 | 42 |
| **sum** | | 778 / 694 | **652** |
| probe (empty window) | | 21 / 7 | 0 |

The two unsigned-heavy pairs dominate. `(0, 91)` is the early return; treat it as a smoke check, not a speed target.

## Memory (instrumented ELF)

| Section | Bytes |
| :--- | ---: |
| `.text` (all: `_start`, `main`, `gcd`, `print_u32`, counters) | 792 |
| `.rodata` (`vals`, strings, `pow10`) | 124 |
| `.bss` (`buf`, sums) | 24 |
| `.stack` (reserved, not in the image) | 4100 |
| `gcd` symbol only | 124 |

No `.data`. Compare `.text` / `.rodata` / `.bss` as the spec asks (`size -A`); compare the `gcd` symbol when the change is only inside the algorithm.

## Later (empty until we have them)

- gcc `-O0` / `-O2` / `-Os` of the C `gcd`, same six pairs, same window.
- Handwritten vs fastest gcc (cycles) and vs smallest gcc (size).
