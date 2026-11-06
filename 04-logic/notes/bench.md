# Fixed (Quiz 3 C) bench log

Measured on rv32emu in `arch2026-progs`; `cycle` ≡ `instret` (CPI = 1).
ELF builds use a temporary linkable C `q_mul` (16×16 magnitudes); committed `fixed.c` may still be the direct `int64_t` draft.

Reproduce:

```bash
make build/fixed/O2/fixed.elf
third_party/rv32emu/build/rv32emu build/fixed/O2/fixed.elf
scripts/driver.py --prog fixed
```

## Log

| Commit | Change | `@@perf` C op1/op2/op3/q_mul | `@@perf` ASM | ASM op3 bench | ASM `.text` | driver |
| :--- | :--- | ---: | ---: | ---: | ---: | :--- |
| `db96067` | baseline `op1`: top `beqz`, `mv`, `j` | 169 / 6 / 11 / 519 | 233 / 8 / 12 / 399 | 259 | 240 B | op1 FAIL 0.81× |
| `8a202df` | `op1` bottom-tested fall-through | 169 / 6 / 11 / 519 | 169 / 8 / 12 / 399 | 259 | 236 B | 55/55; op1 1.00× |
| `3e24f41` | `op2`: plain `sub` | 169 / 6 / 11 / 519 | 169 / 6 / 12 / 399 | 259 | 220 B | 55/55; op2 1.00× |
| (this) | `op3`: one `and` + `andi` for LSB carry | 169 / 6 / 11 / 519 | 169 / 6 / 11 / 399 | 243 | 216 B | 55/55; op3 1.00× |

## Detail after tightened `op3` (`-O2`)

| Function | C worst | ASM worst | C bench | ASM bench | checksum |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `op1` | 169 | 169 | 453 | 453 | 3759865892 |
| `op2` | 6 | 6 | 163 | 163 | 538247170 |
| `op3` | 11 | 11 | 243 | 243 | 4027416571 |
| `q_mul` | 519 | 399 | 5199 | 3613 | 1538001573 |

Symbol sizes: `op1_asm` 36 B, `op2_asm` 8 B, `op3_asm` 28 B, `q_mul_asm` 144 B.
