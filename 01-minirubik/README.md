# HW1 minirubik → bare-metal

同一個 2×2 solver，換成 rv32emu 的 `write`(64) / `exit`(93)，加上 `start.S` 和 4 KiB stack。LED 拿掉。

C 與組語都要在 guest 上跑。host 參考：[`../../2026-hw1-minirubik/`](../../2026-hw1-minirubik/README.md)。
