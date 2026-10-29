<!-- source: https://hackmd.io/@sysprog/Sko2Ja5pel -->

---
tags: computer-arch
---

# Lab2: RISC-V Instruction Set Simulator and System Emulator

## Overview

[rv32emu](https://github.com/sysprog21/rv32emu) is an emulator for the 32-bit RISC-V architecture (RV32), written mostly in C99 with C11 atomics. It covers RV32I and RV32E plus the M, A, F, and C extensions and the Zba/Zbb/Zbc/Zbs bit-manipulation extensions. It runs in two modes:

- User mode: loads a statically linked ELF executable and services its `ecall` requests through a newlib-compatible system call layer. SDL2-backed calls let guest programs draw graphics and play audio, which is enough to run Doom and Quake.
- System mode: models the MMU (Sv32), privilege levels, a UART, a timer, and virtio devices, which is enough to boot an RV32 Linux kernel.

Execution starts in an interpreter that profiles basic blocks. Hot blocks are compiled by a lightweight tier-1 JIT, and the hottest paths can go to an LLVM-based tier-2 compiler. The design is described in the VMIL'24 paper "[Accelerate RISC-V Instruction Set Simulation by Tiered JIT Compilation](https://doi.org/10.1145/3689490.3690399)" by Yen-Fu Chen, Meng-Hung Chen, Ching-Chun Huang, and Chia-Heng Tu of National Cheng Kung University ([talk page](https://2024.splashcon.org/details/vmil-2024-papers/4/Accelerate-RISC-V-Instruction-Set-Simulation-by-Tiered-JIT-Compilation)).

This lab builds rv32emu, examines a minimal RISC-V program with the GNU binutils, runs a bare-metal test suite, and boots Linux. The commands below were verified on Ubuntu Linux 24.04 (x86-64) against rv32emu master as of October 2026 (commit `49b0a5a`); later commits may change the outputs shown, and `git checkout 49b0a5a` reproduces them exactly.

## Try It in the Browser

rv32emu also compiles to WebAssembly with [Emscripten](https://emscripten.org/docs/getting_started/downloads.html), so both modes run in a web page with no local setup:

- [Demo landing page](https://sysprog21.github.io/rv32emu-demo/)
- [User-mode emulation](https://sysprog21.github.io/rv32emu-demo/user/): pick a prebuilt ELF (Doom, Quake, and smaller programs) from the drop-down menu and press "Run"
- [System emulation](https://sysprog21.github.io/rv32emu-demo/system/): press "Run Linux" to boot a kernel and a Buildroot userland in the browser

The interpreter dispatches instructions through tail calls, so the WebAssembly build depends on the Wasm tail-call feature: Chrome 112, Firefox 121, Safari 18.2, or later. To build and serve the WebAssembly port locally, follow [docs/wasm.md](https://github.com/sysprog21/rv32emu/blob/master/docs/wasm.md). In short, with Emscripten 3.1.51 activated:

```shell
make wasm_defconfig          # or wasm_system_defconfig for system emulation
make CC=emcc prepare-web -j8
make CC=emcc serve-web
```

`prepare-web` builds the emulator and stages the page; `serve-web` starts a local web server and prints its address. The documented shortcut `make CC=emcc start-web -j8` names both as independent prerequisites, so a parallel build can launch the server before the files are in place. The demo page is useful for a quick look; the remainder of this lab uses a native build, which runs faster and exposes the tools.

## Setup

:::warning
These instructions are verified on Ubuntu Linux 24.04 LTS, which also works inside a virtual machine such as [VirtualBox](https://www.virtualbox.org/). macOS on Apple silicon is exercised by upstream CI; replace `linux-x64` with `darwin-arm64` in the toolchain file name and use Homebrew for the libraries.
:::

### RISC-V GNU Toolchain

Install the [xPack GNU RISC-V Embedded GCC](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/), a prebuilt bare-metal (`riscv-none-elf`) toolchain:

```shell
cd /tmp
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v14.2.0-3/xpack-riscv-none-elf-gcc-14.2.0-3-linux-x64.tar.gz
tar zxvf xpack-riscv-none-elf-gcc-14.2.0-3-linux-x64.tar.gz
cp -af xpack-riscv-none-elf-gcc-14.2.0-3 $HOME/riscv-none-elf-gcc
echo "export PATH=$HOME/riscv-none-elf-gcc/bin:\$PATH" > $HOME/riscv-none-elf-gcc/setenv
```

Newer releases (GCC 15.2 as of this writing) are listed on the [release page](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases); this lab was tested with 14.2.0-3. Load the environment in every new shell, then confirm the compiler is found:

```shell
source $HOME/riscv-none-elf-gcc/setenv
riscv-none-elf-gcc -v
```

The last line of the output should read:

```
gcc version 14.2.0 (xPack GNU RISC-V Embedded GCC x86_64)
```

The rv32emu build scripts search `PATH` for the prefixes `riscv-none-elf-`, `riscv32-unknown-elf-`, `riscv64-unknown-elf-`, and `riscv-none-embed-`, in that order.

### Libraries

The build scripts need a host C compiler, `git`, Python 3 (for Kconfig), `bc` (for memory-size arithmetic), and `curl` (for downloading test binaries and game data). On Ubuntu: `sudo apt install build-essential git python3 bc curl`.

rv32emu uses [SDL2](https://www.libsdl.org/) and SDL2_mixer for graphics and audio:

- Ubuntu/Debian: `sudo apt install libsdl2-dev libsdl2-mixer-dev`
- macOS: `brew install sdl2 sdl2_mixer`

System emulation also needs the device tree compiler: `sudo apt install device-tree-compiler` on Ubuntu, `brew install dtc` on macOS.

### Build and Test

rv32emu uses a Kconfig-based build. A configuration must be selected before the first build; a bare `make` stops with `.config required. Run 'make defconfig' first.`

```shell
git clone https://github.com/sysprog21/rv32emu
cd rv32emu
make defconfig
make
make check
```

`make defconfig` enables the M, A, F, C, and Zicsr extensions, SDL, and the tier-1 JIT. Other presets include `interpreter_defconfig`, `jit_defconfig` (adds the LLVM tier-2 compiler), and `system_defconfig`; `make config` opens an interactive menu. See [docs/build.md](https://github.com/sysprog21/rv32emu/blob/master/docs/build.md) for every option.

`make check` runs regression programs and compares their output with known results. Some are built on the spot with the cross toolchain; others (`puzzle`, `fcalc`, `pi`) are prebuilt binaries fetched from [rv32emu-prebuilt](https://github.com/sysprog21/rv32emu-prebuilt) and verified by SHA-1. On a fresh clone, `SHA-1 verification failed!` followed by a re-fetch is expected, since nothing has been downloaded yet. Each test line should end in `[OK]`:

```
Running  hello.elf ... [OK]
...
Running  puzzle ... [OK]
Running  fcalc ... [OK]
Running  pi ... [OK]
```

Run a single program by passing it to the emulator:

```shell
build/rv32emu build/hello.elf
```

It prints `Hello World!` five times and exits with status 0.

## Inspecting a RISC-V Executable

`build/hello.elf` is assembled from [`tests/asm-hello/hello.S`](https://github.com/sysprog21/rv32emu/tree/master/tests/asm-hello). It calls `write` (system call 64) five times and then `exit` (system call 93), passing the call number in `a7` and the arguments in `a0` to `a2`, as the RISC-V Linux and newlib conventions do. Rebuild it from source:

```shell
make -C tests/asm-hello
```

The Makefile assembles with `-march=rv32i -mabi=ilp32`: the base integer ISA only, and the [ILP32 ABI](https://github.com/riscv-non-isa/riscv-elf-psabi-doc/blob/master/riscv-cc.adoc), in which `int`, `long`, and pointers are 32 bits wide and floating-point values are passed in integer registers. The linker script `hello.ld` places the program at address 0. The output, `tests/asm-hello/hello.elf`, is byte-for-byte identical to the committed `build/hello.elf`.

### objdump: Disassembly

```shell
riscv-none-elf-objdump -d build/hello.elf
```

```
build/hello.elf:     file format elf32-littleriscv


Disassembly of section .text:

00000000 <_start>:
   0:	00000293          	li	t0,0
   4:	00500313          	li	t1,5
   8:	0040006f          	j	c <_start+0xc>
   c:	00000013          	nop

00000010 <loop>:
  10:	02628063          	beq	t0,t1,30 <end>
  14:	04000893          	li	a7,64
  18:	00100513          	li	a0,1
  1c:	03c00593          	li	a1,60
  20:	00d00613          	li	a2,13
  24:	00000073          	ecall
  28:	00128293          	addi	t0,t0,1
  2c:	fe5ff06f          	j	10 <loop>

00000030 <end>:
  30:	05d00893          	li	a7,93
  34:	00000513          	li	a0,0
  38:	00000073          	ecall
```

The source loads the string address with `la a1, str`, which the assembler expands into an `auipc`/`addi` pair marked with `R_RISCV_RELAX` (visible with `objdump -dr` on `hello.o`). Because `str` ends up at address 0x3C, which fits in a 12-bit immediate, the linker relaxes the pair into a single `li a1,60` and shifts the code that follows. Linking with `--no-relax` keeps both instructions and grows the program by 4 bytes.

### readelf: ELF Header

```shell
riscv-none-elf-readelf -h build/hello.elf
```

```
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00 
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              EXEC (Executable file)
  Machine:                           RISC-V
  Version:                           0x1
  Entry point address:               0x0
  Start of program headers:          52 (bytes into file)
  Start of section headers:          4532 (bytes into file)
  Flags:                             0x0
  Size of this header:               52 (bytes)
  Size of program headers:           32 (bytes)
  Number of program headers:         2
  Size of section headers:           40 (bytes)
  Number of section headers:         7
  Section header string table index: 6
```

`Flags: 0x0` records the soft-float ABI without the C extension; an `-mabi=ilp32f` or RVC object would set bits here. The emulator's ELF loader reads the program headers to map the segments and jumps to the entry point.

### size: Section Sizes

```shell
riscv-none-elf-size build/hello.elf
```

```
   text	   data	    bss	    dec	    hex	filename
     73	      0	      0	     73	     49	build/hello.elf
```

`size` counts read-only data as `text`: 60 bytes of code (15 instructions) plus the 13-byte string `"Hello World!\n"` in `.rodata`.

## Game Demos

With SDL enabled (the default), rv32emu runs two id Software classics ported to RV32. Each target downloads the game data on first use:

```shell
make doom
make quake
```

![Doom gameplay](https://imgur.com/bLc5LG8.gif)

![Quake gameplay](https://imgur.com/gXKb7D0.gif)

Doom comes from [doom_riscv](https://github.com/sysprog21/doom_riscv) and Quake from [quake-embedded](https://github.com/sysprog21/quake-embedded). Quake uses single-precision floating point, so the `quake` target exists only when the F extension is enabled, as it is in `defconfig`. Key bindings are listed in [docs/demo.md](https://github.com/sysprog21/rv32emu/blob/master/docs/demo.md).

## System Emulation

A system-mode build (`CONFIG_SYSTEM`) adds privilege levels, trap delegation, the Sv32 MMU, and memory-mapped devices. It runs in one of two ways:

- Without `ELF_LOADER` (the default for `system_defconfig`), the emulator boots a kernel image (`-k`) with a root filesystem.
- With `ELF_LOADER`, it loads an ELF executable directly, which suits bare-metal tests that install their own trap handlers.

### Booting Linux

```shell
make distclean
make system_defconfig
make system
```

`make system` fetches a prebuilt kernel and Buildroot root filesystem from rv32emu-prebuilt, then runs `build/rv32emu -k build/linux-image/Image -x vblk:build/linux-image/rootfs.ext4,rootfs`. Log in as `root`:

```
# uname -a
Linux buildroot 6.1.188 #1 Tue Sep 29 17:18:07 UTC 2026 riscv32 GNU/Linux
# cat /proc/cpuinfo | head -8
processor	: 0
hart		: 0
isa		: rv32ima
mmu		: sv32
mvendorid	: 0x12345678
marchid		: 0x80000001
mimpid		: 0x1
```

`poweroff` shuts the guest down and returns to the host shell. The root filesystem image is mounted read-write, and changes persist when the emulator is invoked directly with the command above; `make system` re-verifies the images by SHA-1 and fetches them again, discarding any changes. [docs/system.md](https://github.com/sysprog21/rv32emu/blob/master/docs/system.md) covers initrd boot, extra virtio block devices, kernel command lines, and building the images from source.

### Misaligned Access Test

[`tests/system/alignment`](https://github.com/sysprog21/rv32emu/blob/master/tests/system/alignment/misalign.S) installs a supervisor trap handler through `stvec`, then performs a misaligned load, a misaligned store, and a call to a function placed at the odd address 0x10000007. The three accesses should raise cause 4, 6, and 0 respectively and enter the handler, which skips the faulting access or returns to the caller:

```shell
make -C tests/system/alignment
make distclean
make system_defconfig
make ENABLE_ELF_LOADER=1 ENABLE_EXT_C=0 misalign-in-blk-emu
```

The last command should end with `Running  misalign.elf ... [OK]`. The check is weak: `main.c` prints each `PASSED` line unconditionally, and the target compares only the last line, so `[OK]` shows that the program ran to completion, not that each trap was taken. Confirming trap delivery needs a debugger (rv32emu has a GDB stub) or a handler that records each cause.

`ENABLE_EXT_C=0` matters because `jalr` clears bit 0 of the target, turning 0x10000007 into 0x10000006. That address is 2-byte aligned, which is legal when the C extension is present and misaligned only when instructions must be 4-byte aligned. With C left enabled, no fetch exception is raised, the emulator aborts with `Failed to allocate or translate block at PC=0x10000006`, and the check reports `Failed`. Linking the test prints a warning that a LOAD segment has RWX permissions; bare-metal images commonly merge code and data into one segment, and the warning is harmless here.

`ENABLE_*` variables on the `make` command line override the selected configuration for that invocation only. They are not written back to `.config`.

## Bare-Metal Playground

The [playground](https://gist.github.com/jserv/5f682ac880773cab69e3564f4f20d60a) is a freestanding RV32I program that brings its own startup code, linker script, and helper routines, with no C library. It measures a ChaCha20 cipher written in assembly and software BFloat16 arithmetic by reading the RISC-V performance counters. Clone it into the rv32emu tree, since its Makefile includes `../../../mk/toolchain.mk` to locate the cross compiler:

```shell
git clone https://gist.github.com/jserv/5f682ac880773cab69e3564f4f20d60a tests/system/playground
cd tests/system/playground
make
```

`make` assembles `start.S`, `perfcounter.S`, and `chacha20_asm.S` with `-march=rv32izicsr`, compiles `main.c` with `-march=rv32i_zicsr`, and links them into `test.elf` with `linker.ld`. The assembler warns that the `.S` files lack a final newline, and the linker repeats the RWX warning; neither affects the result.

The program communicates only through the `write` and `exit` system calls, so it runs on a user-mode build as well as on a system-mode build with `ELF_LOADER`, and the counts below are identical on both, with or without the JIT. Run it with the emulator built in the previous section:

```shell
../../../build/rv32emu test.elf
```

The gist also provides `make run`, but that target checks for `ENABLE_ELF_LOADER=1` and `ENABLE_SYSTEM=1` in `build/.config`. That file belongs to the older build system; the Kconfig build keeps its configuration in `.config` at the top level, so `make run` stops with `Error: ENABLE_ELF_LOADER=1 not set` even when the emulator is configured correctly. Invoke the emulator directly as shown. The output, abridged to the ChaCha20 test and the first BFloat16 test:

```
=== ChaCha20 Tests ===

Test 0: ChaCha20 (RISC-V Assembly)
Test: ChaCha20
  ChaCha20 RFC 7539: PASSED
  Cycles: 6797
  Instructions: 6797


=== BFloat16 Tests ===

Test 1: bf16_add
Test: bf16_add
  1.0 + 1.0 = 4000
  PASSED
  Cycles: 432
  Instructions: 432
...
=== All Tests Completed ===
```

The remaining tests report 373 (`bf16_sub`), 464 (`bf16_mul`), 624 (`bf16_div`), and 239 (`bf16_special_cases`). `make dump` pipes `riscv-none-elf-objdump -Ds test.elf` into `less` for inspection.

### Startup Code and Memory Layout

`linker.ld` places `_start` first at address 0x10000, followed by the rest of `.text`, `.data`, and `.bss`. It reserves a 4 KiB, 16-byte-aligned stack after `.bss` in a `NOLOAD` section and exports `__bss_start`, `__bss_end`, and `__stack_top`:

```
SECTIONS
{
  . = 0x10000;
  .text : {
    *(.text._start)
    *(.text)
  }
  .data : { *(.data) }
  .bss : {
    __bss_start = .;
    *(.bss)
    __bss_end = .;
  }
  .stack (NOLOAD) : {
    . = ALIGN(16);
    . += 4096;
    __stack_top = .;
  }
}
```

`start.S` performs the work a C runtime normally does before `main`: it loads `sp` with `__stack_top`, zeroes `.bss` one word at a time, calls `main`, and, if `main` returns, issues `exit` (system call 93) with status 0.

RV32I has no multiply instruction, so GCC lowers `*` to a call to `__mulsi3`, a libgcc routine. Because the program is linked without libgcc, `main.c` supplies its own shift-and-add `__mulsi3`, along with `memcpy` and integer-to-string helpers for printing. Each such call costs dozens of instructions, which shows up in the counts.

### Performance Counters

`perfcounter.S` reads the 64-bit `cycle` (CSR 0xC00/0xC80) and `instret` (0xC02/0xC82) counters. On RV32 each counter is split into two 32-bit halves, and the low half may wrap between the two reads, pairing a stale high half with a fresh low half. The routine therefore reads the high half, the low half, then the high half again, and retries if the two high values differ:

```
get_cycles:
    csrr a1, cycleh
    csrr a0, cycle
    csrr a2, cycleh
    bne a1, a2, get_cycles
    ret
```

`csrr a1, cycleh` is the same instruction as the `rdcycleh a1` pseudo-instruction. `get_instret` is identical apart from the CSR names.

The test output reports equal cycle and instruction counts because rv32emu has no timing model: [`src/emulate.c`](https://github.com/sysprog21/rv32emu/blob/master/src/emulate.c) maps `cycle`, `instret`, and their high halves onto the same counter, which counts executed guest instructions in the interpreter and both JIT tiers. The "Cycles" figures are therefore instruction counts. They are useful for comparing algorithms on the same ISA, not for predicting time on hardware with pipelines and caches. Each measured interval also includes the `write` system calls that print each test's header and result.

### ChaCha20 in Assembly

`chacha20_asm.S` implements the ChaCha20 stream cipher of [RFC 7539](https://www.rfc-editor.org/rfc/rfc7539) (since superseded by [RFC 8439](https://www.rfc-editor.org/rfc/rfc8439), which leaves the algorithm unchanged). The 16-word state, four constant words followed by a 256-bit key, a 32-bit block counter, and a 96-bit nonce, is held entirely in registers. The quarter round adds, XORs, and rotates (ARX); RV32I has no rotate instruction, so each rotation is a pair of shifts combined with XOR:

```
.macro quarterround a,b,c,d, t
    add     \a, \a, \b
    xor     \d, \d, \a
    slli    \t, \d, 16
    srli    \d, \d, 16
    xor     \d, \d, \t
    # ... three more add/xor/rotate steps by 12, 8, and 7 bits
.endm
```

A `tworounds` macro applies four column quarter rounds and four diagonal quarter rounds, one column round plus one diagonal round in RFC terms; ten invocations give the 20 rounds of a block. The test encrypts the 114-byte "sunscreen" plaintext from RFC 7539 Section 2.4.2 (key 00 to 1F, counter 1), which spans two 64-byte blocks, the second one partial, and compares the result with the RFC ciphertext. The rounds contain no branches, and the branches outside them depend only on the message length, never on the key or data.

Passing this vector does not make the routine correct for every input. The partial-block path reads and writes whole words and masks the keystream, so for the 114-byte message it reads 2 bytes past the input and writes 2 zero bytes past the output buffer. It also stops after offset 56, so a final block of 61 to 63 bytes leaves its last bytes unencrypted. The prologue reserves 44 bytes of stack, which breaks the ILP32 rule that `sp` stays 16-byte aligned. Fixing these (byte-wise tail handling, a `lastwords 60` step, and a 48-byte frame) and adding test vectors that exercise them makes a good exercise.

### Software BFloat16

BFloat16 keeps the sign bit and the 8-bit exponent of IEEE 754 single precision but only 7 fraction bits, so its range matches `float` at reduced precision. `main.c` implements addition, subtraction, multiplication, and division directly on the 16-bit encoding, with integer operations only:

- Addition aligns the significands by the exponent difference, adds or subtracts them, and renormalizes.
- Subtraction flips the sign bit of the second operand and calls the adder.
- Multiplication multiplies the 8-bit significands (through `__mulsi3`) and adds the exponents.
- Division runs a 16-step restoring shift-and-subtract loop.

The tests use exact cases (1.0 + 1.0, 3.0 − 2.0, 2.0 × 3.0, and 6.0 ÷ 2.0) plus zero, NaN, and infinity classification, which hide several departures from IEEE 754 behavior. Compiling the routines on the host and calling them directly shows:

- Results are truncated rather than rounded to nearest even, except that addition returns the larger operand unchanged when the exponents differ by more than 8.
- Addition that overflows returns NaN (`0x7F00 + 0x7F00` gives `0x7FC0`) instead of infinity.
- A product that should be subnormal is flushed to zero: `0x0080 × 0x3F00` (the smallest normal times 0.5) gives `0x0000` instead of `0x0040`, because the implicit leading bit is masked off before the subnormal shift.
- Division with an infinite divisor returns zero even when the dividend is NaN.

Treat the routines as a starting point: fixing these cases and adding tests that cover rounding, overflow, and subnormals is a natural extension.

## Troubleshooting

- `.config required. Run 'make defconfig' first.`: select a configuration (`make defconfig` or `make system_defconfig`). `make distclean` removes `.config`, so run it again after cleaning.
- `riscv-none-elf-gcc: command not found`: run `source $HOME/riscv-none-elf-gcc/setenv` in the current shell.
- `Error: ENABLE_ELF_LOADER=1 not set` from the playground's `make run`: the target checks the old `build/.config`; run `../../../build/rv32emu test.elf` instead.
- `make quake` prints `Nothing to be done for 'quake'`: the F extension or SDL is disabled in the current configuration.

## References

- [rv32emu documentation](https://github.com/sysprog21/rv32emu/tree/master/docs): build options, system emulation, WebAssembly, GDB remote debugging
- [RISC-V ratified specifications](https://riscv.org/specifications/ratified/): the unprivileged ISA (RV32I, Zicsr, counters) and the privileged architecture (traps, Sv32)
- [RISC-V ELF psABI](https://github.com/riscv-non-isa/riscv-elf-psabi-doc): calling convention, register usage, relocations, and linker relaxation
- [RFC 8439](https://www.rfc-editor.org/rfc/rfc8439): ChaCha20 and Poly1305
- [bfloat16 floating-point format](https://en.wikipedia.org/wiki/Bfloat16_floating-point_format)
- [GNU ld linker scripts](https://sourceware.org/binutils/docs/ld/Scripts.html)