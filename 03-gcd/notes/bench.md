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
| `958ff64` | same `gcd`, CSR window + `print_cycret` (baseline to optimize against) | 652 | 652 | 1.00 | 792 | 124 | 24 | 124 |
| `e7c4534` | `even_loop`: test at the bottom, `beq` back to body, fall into `gcd_loop` | 613 | 613 | 1.00 | 800 | 124 | 24 | 132 |
| `2b46ee8` | `strip_a` / `strip_b`: same bottom-tested inner loops | 593 | 593 | 1.00 | 808 | 124 | 24 | 140 |
| `d489786` | `a > b` subtract falls into `gcd_loop` (**kept**) | 578 | 578 | 1.00 | 812 | 124 | 24 | 144 |
| `de064c5` | `larger_b` (`a < b`) falls into `gcd_loop` (not kept) | 592 | 592 | 1.00 | 808 | 124 | 24 | 140 |
| `99e8e2b` | after subtract, only strip the side just made even | 546 | 546 | 1.00 | 836 | 124 | 24 | 168 |
| `577ecda` | reorder: `strip_b` falls into `odd_sub`, `strip_a1` into `strip_b` | 544 | 544 | 1.00 | 828 | 124 | 24 | 160 |

Append a row for every later commit that changes `gcd` (fall-through, ctz, `sltu`, …). Tooling-only commits stay out, same as Homework 1.

## Baseline per pair (`958ff64`)

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

### After `even_loop` fall-through (`e7c4534`)

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `958ff64` |
| :--- | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 86 / 72 | 65 | 0 |
| (4096, 3072) | 1024 | 115 / 101 | 94 | −10 |
| (0xF0000000, 0x30000000) | 805306368 | 219 / 205 | 198 | −28 |
| (0x80000001, 3) | 3 | 229 / 215 | 208 | 0 |
| (0, 91) | 91 | 28 / 14 | 7 | 0 |
| (6, 10) | 2 | 62 / 48 | 41 | −1 |
| **sum** | | 739 / 655 | **613** | **−39** |

### After `strip_a` / `strip_b` fall-through (`2b46ee8`)

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `e7c4534` |
| :--- | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 83 / 69 | 62 | −3 |
| (4096, 3072) | 1024 | 113 / 99 | 92 | −2 |
| (0xF0000000, 0x30000000) | 805306368 | 218 / 204 | 197 | −1 |
| (0x80000001, 3) | 3 | 215 / 201 | 194 | −14 |
| (0, 91) | 91 | 28 / 14 | 7 | 0 |
| (6, 10) | 2 | 62 / 48 | 41 | 0 |
| **sum** | | 719 / 635 | **593** | **−20** |

### After `a > b` falls into `gcd_loop` (`d489786`, kept)

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `2b46ee8` |
| :--- | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 82 / 68 | 61 | −1 |
| (4096, 3072) | 1024 | 114 / 100 | 93 | **+1** |
| (0xF0000000, 0x30000000) | 805306368 | 218 / 204 | 197 | 0 |
| (0x80000001, 3) | 3 | 200 / 186 | 179 | −15 |
| (0, 91) | 91 | 28 / 14 | 7 | 0 |
| (6, 10) | 2 | 62 / 48 | 41 | 0 |
| **sum** | | 704 / 620 | **578** | **−15** |

`(4096, 3072)` pays the extra `j gcd_loop` after `even_loop_inner` once. `(0x80000001, 3)` is the `a > b` heavy pair.

### After `larger_b` (`a < b`) falls into `gcd_loop` (`de064c5`, not kept)

Compare with the `a > b` layout above. Not kept: `(0x80000001, 3)` is the hot `a > b` arm.

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `2b46ee8` | Δ vs `a > b` layout |
| :--- | ---: | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 81 / 67 | 60 | −2 | −1 |
| (4096, 3072) | 1024 | 113 / 99 | 92 | 0 | −1 |
| (0xF0000000, 0x30000000) | 805306368 | 219 / 205 | 198 | +1 | +1 |
| (0x80000001, 3) | 3 | 215 / 201 | 194 | 0 | **+15** |
| (0, 91) | 91 | 28 / 14 | 7 | 0 | 0 |
| (6, 10) | 2 | 62 / 48 | 41 | 0 | 0 |
| **sum** | | 718 / 634 | **592** | **−1** | **+14** |

### After only-strip-the-changed-side (`99e8e2b`)

First entry still goes through `strip_a1` then `strip_b`. After `a > b`, only `strip_a`; after `larger_b`, only `strip_b`.

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `d489786` |
| :--- | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 75 / 61 | 54 | −7 |
| (4096, 3072) | 1024 | 112 / 98 | 91 | −2 |
| (0xF0000000, 0x30000000) | 805306368 | 216 / 202 | 195 | −2 |
| (0x80000001, 3) | 3 | 184 / 170 | 163 | **−16** |
| (0, 91) | 91 | 28 / 14 | 7 | 0 |
| (6, 10) | 2 | 57 / 43 | 36 | −5 |
| **sum** | | 672 / 588 | **546** | **−32** |

`(0x80000001, 3)` no longer pays `strip_b` on the `a > b` arm. `gcd` grew 144 → 168 for the extra `strip_a1` copy.

### After block reorder (`577ecda`)

`strip_a1_inner` falls into `strip_b`; `strip_b_inner` falls into `odd_sub`. `strip_a_inner` still `j odd_sub`.

| Pair | Result | Window cyc / iret | Gcd-only | Δ vs `99e8e2b` |
| :--- | ---: | ---: | ---: | ---: |
| (1071, 462) | 21 | 74 / 60 | 53 | −1 |
| (4096, 3072) | 1024 | 111 / 97 | 90 | −1 |
| (0xF0000000, 0x30000000) | 805306368 | 216 / 202 | 195 | 0 |
| (0x80000001, 3) | 3 | 184 / 170 | 163 | 0 |
| (0, 91) | 91 | 28 / 14 | 7 | 0 |
| (6, 10) | 2 | 57 / 43 | 36 | 0 |
| **sum** | | 670 / 586 | **544** | **−2** |

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
