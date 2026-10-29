# Quiz 2 A: binary GCD

Host C first, then the same algorithm on rv32emu.

```bash
make test
```

[`gcd.c`](gcd.c) is the host harness: twelve cases (the six Quiz pairs, zeros, coprimes, and both argument orders). `main` also calls `gcd(b, a)`.

Handwritten RV32I is [`gcd.S`](gcd.S). Labels match the C (`even_loop` / `gcd_loop` / `odd_sub`). `_start` is already there.

```bash
source ../env.sh
make run-asm
```

Expected Quiz lines:

```
f(1071, 462) = 21
f(4096, 3072) = 1024
f(4026531840, 805306368) = 805306368
f(2147483649, 3) = 3
f(0, 91) = 91
f(6, 10) = 2
```

Bench log (same row-per-commit layout as Homework 1 stage 5): [`notes/bench.md`](notes/bench.md). Counts are **gcd only**, not `print_u32`. On rv32emu, `cycle` and `instret` are the same counter; CPI after subtracting the probe is 1.

English note draft: [`notes/hackmd.md`](notes/hackmd.md). Recheck the pinned-commit links before pasting into HackMD.

Still open: micro-test on the guest, and gcc `-O2`/`-Os` vs handwritten cycles and size.

Solution write-up: [Quiz 2](https://hackmd.io/@sysprog/arch2026-quiz2).
