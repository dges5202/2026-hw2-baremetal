# Fixed (Quiz 3 C) bench log

Measured on rv32emu in `arch2026-progs`; `cycle` ≡ `instret` (CPI = 1).
C `q_mul` uses a temporary linkable 16×16 magnitude form only for the ELF under test; the committed `fixed.c` may still be the direct `int64_t` draft.

Reproduce:

```bash
cd ../arch2026-progs   # or your harness tree
make build/fixed/O2/fixed.elf
third_party/rv32emu/build/rv32emu build/fixed/O2/fixed.elf
scripts/driver.py --prog fixed
```

## Log

| Commit | Change | `@@perf` C op1/op2/op3/q_mul | `@@perf` ASM | ASM op1 bench | ASM `.text` | driver op1 |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| (this) | baseline `op1`: top `beqz`, `mv`, `j` | 169 / 6 / 11 / 519 | 233 / 8 / 12 / 399 | 537 | 240 B | FAIL 27.4 vs C 22.1 (0.81×) |

## Baseline detail (`-O2`)

| Function | C worst | ASM worst | C bench | ASM bench | checksum |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `op1` | 169 | 233 | 453 | 537 | 3759865892 |
| `op2` | 6 | 8 | 163 | 179 | 538247170 |
| `op3` | 11 | 12 | 243 | 259 | 4027416571 |
| `q_mul` | 519 | 399 | 5199 | 3613 | 1538001573 |

Symbol sizes: `op1_asm` 40 B, `op2_asm` 24 B, `op3_asm` 32 B, `q_mul_asm` 144 B.
