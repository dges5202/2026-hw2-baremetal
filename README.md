# Assignment 2: Complete Applications

NCKU CSIE Computer Architecture, Fall 2026.

- Spec: [Assignment 2: Complete Applications](https://hackmd.io/@sysprog/2026-arch-homework2) (local snapshot: [`spec.md`](spec.md))
- Repository: https://github.com/dges5202/2026-hw2-baremetal
- Due: **2026-11-15 23:59 (GMT+8)**

The spec page noted a possible update on **2026-10-28 13:00**. The CodeTrial PIN was due in `@gs.ncku.edu.tw` mailboxes before 17:00 that day.

## In one sentence

Port four programs (Homework 1 minirubik, Quiz 1 BFloat16, Quiz 2 binary GCD, Quiz 3 fixed-point / bitwise logic) to a **freestanding RV32I** environment on [rv32emu](https://github.com/sysprog21/rv32emu). Each program needs a C version, handwritten assembly, and a micro-test suite. Measure instruction counts with CSRs; the handwritten code should compete with gcc on speed and on size. Finish with a **recorded CodeTrial mock interview** (no recording means the assignment is not accepted).

## Deliverables

| Item | Due | Notes |
| --- | --- | --- |
| GitHub repo (C, assembly, `Makefile`, linker, startup, tests for all four programs) | Nov 15 23:59 | Do not clone the whole rv32emu tree |
| HackMD note, in English | Nov 15 23:59 | Short excerpts linked to pinned commits |
| CodeTrial mock-interview recording | announced on the spec page | No recording: assignment not accepted |
| [Google form](https://forms.gle/GyNbSQzNoXdEELdFA) | Nov 15 | Repo URL and HackMD URL |

Using any AI, TTS, or translation help **during the interview** zeroes the semester assignment grade.

## The four programs

Each needs C, handwritten RV32I, and a complete micro-test suite. Build with `-march=rv32izicsr -mabi=ilp32`. `mul` / `div` / `rem` and floating-point instructions are forbidden; supply helpers the compiler emits (`__mulsi3`, `memset`, …). Talk to the emulator only through `write` (64) and `exit` (93).

| # | Source | What it does | RV32I pinch point |
| --- | --- | --- | --- |
| 1 | HW1 minirubik | 2×2 cube solver, moved from Ripes to rv32emu | Replace env calls with `write`/`exit`; **4 KiB stack** |
| 2 | Quiz 1 B | BFloat16 arithmetic (mantissa product, square root) | No `mul`: 8-bit×8-bit by hand; treat binary32 as `uint32_t` bits, no `float` math |
| 3 | Quiz 2 A | Binary GCD (shift / subtract, no divider) | Already RV32I; decimal print without division; `ctz` / `sltu` for further cuts |
| 4 | Quiz 3 C | `op1`/`op2`/`op3` bitwise add/sub, plus Q11.20 `q_mul` | `q_mul` needs 32×32→64 signed multiply; do not port the adder-delay / sequential-circuit questions |

Quiz 3 C parts 2–4 (adder delay, sequential circuit) are not programs and are not ported.

## Hard rules (graded)

- No libc, no libgcc, no heap (the playground has no allocator; a bump allocator is fine if you really need one).
- Image loads at `0x10000`. Default stack is 4 KiB; grow `linker.ld` only if you measure that you must.
- Tests: [micro-test](https://github.com/trmckay/micro-test), `-D NO_STD`, with its POSIX / `strlen` dependencies stripped (the spec lists the edits).
- Measure with the playground `get_cycles()` / `get_instret()`. Do not use the `ticks.c` helper; an optimizing compiler can delete the work it times.
- rv32emu **has no timing model**: `cycle` and `instret` both count executed guest instructions. State that in the note. Report size separately with `size -A` (`.text` / `.rodata` / `.data` / `.bss`).
- Compare handwritten cycles to the fastest gcc build, and handwritten size to the smallest. Every `-O*` you report must pass every micro-test.

## Layout

| Path | Contents |
| --- | --- |
| [`spec.md`](spec.md) | Official spec snapshot (2026-10-27 09:04) |
| [`refs/playground/`](refs/playground/) | [gist](https://gist.github.com/jserv/5f682ac880773cab69e3564f4f20d60a): `start.S`, `linker.ld`, `perfcounter.S`, ChaCha20 sample |
| [`refs/micro-test/`](refs/micro-test/) | `utest.c` / `utest.h` |
| [`refs/hackmd/lab2-bare-metal.md`](refs/hackmd/lab2-bare-metal.md) | Lab 2 |
| [`refs/hackmd/bf16-sine.md`](refs/hackmd/bf16-sine.md) | Reference note (BF16 sine; its FP instructions are not allowed here) |
| [`refs/hackmd/line-draw-fixed-point.md`](refs/hackmd/line-draw-fixed-point.md) | Reference note (fixed-point line drawing) |
| [`refs/rv32emu-files/`](refs/rv32emu-files/) | `ticks.c`, `syscall.md` |
| [`refs/github/codetrial-pr-259.md`](refs/github/codetrial-pr-259.md) | CodeTrial task-mode PR (still open) |
| [`refs/imgs/`](refs/imgs/) | CodeTrial screenshots from the spec page |

Do not write the programs under `refs/`. The submitted tree should contain a playground copied from the gist, with relative paths adjusted.

| Directory | Status |
| --- | --- |
| [`01-minirubik/`](01-minirubik/) | Not started |
| [`02-bf16/`](02-bf16/) | Not started |
| [`03-gcd/`](03-gcd/) | Handwritten RV32I + host C + bench (gcd-only 652→400). micro-test and gcc comparison still open |
| [`04-logic/`](04-logic/) | Not started |

Homework 1 sources: [dges5202/minirubik](https://github.com/dges5202/minirubik). Quiz solutions:

- BFloat16: [Quiz 1](https://hackmd.io/@sysprog/arch2026-quiz1)
- Binary GCD: [Quiz 2](https://hackmd.io/@sysprog/arch2026-quiz2) (title on the paper: Two Operands)
- Two Kinds of Logic: [Quiz 3](https://hackmd.io/@sysprog/arch2026-quiz3)

GCD note draft (English): [`03-gcd/notes/hackmd.md`](03-gcd/notes/hackmd.md).

## Local environment (built and checked)

The emulator lives in [`rv32emu/`](rv32emu/) (**gitignored; do not submit it**). In a new terminal:

```bash
source env.sh
playground-run -O0
playground-run -O2
```

| Item | Recorded 2026-10-27 |
| --- | --- |
| rv32emu | `cab9a11`, `system_defconfig` + `CONFIG_ELF_LOADER=y`, no SDL / no Linux boot (this machine has no libsdl2 or dtc; Homework 2 does not need them) |
| Cross compiler | `riscv64-unknown-elf-gcc` 16.1.0 (same tree as Homework 1) |
| Playground | gist `5f682ac880773cab69e3564f4f20d60a` at `rv32emu/tests/system/playground` |
| Makefile fix | `riscv64-unknown-elf-ld` defaults to elf64; added `-m elf32lriscv` |

Playground `make run`:

| OPT | Result | ChaCha20 cycles / instret |
| --- | --- | --- |
| `-O0` | 8 PASSED, 0 FAILED | 6797 / 6797 (matches the Lab 2 handout) |
| `-O2` | 8 PASSED, 0 FAILED | 4322 / 4323 |

Later ELFs: `rv32emu path/to/prog.elf`.

## Suggested order

1. ~~Build rv32emu from Lab 2.~~ Done.
2. Port micro-test so it can print on bare metal (shared by all four programs).
3. Smallest port first: Quiz 2 GCD ([`03-gcd/`](03-gcd/), `make test` on the host).
4. Quiz 1 BF16, Quiz 3 `q_mul`, then minirubik (the 4 KiB stack is the tight one).
5. For each program, a table of gcc `-O2`/`-O3`/`-Os` vs handwritten assembly.
6. HackMD. In parallel: Gemini / LiveKit / GitHub OAuth, and the CodeTrial PIN mail.
