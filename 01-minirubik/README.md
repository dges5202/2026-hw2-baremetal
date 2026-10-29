# Homework 1 minirubik → bare metal

The same 2×2 solver, talking to rv32emu through `write` (64) / `exit` (93), with `start.S` and a 4 KiB stack. The LED path is dropped.

Both the C version and the handwritten assembly must run on the guest. Host reference: [dges5202/minirubik](https://github.com/dges5202/minirubik).
