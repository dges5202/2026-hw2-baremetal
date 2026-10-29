# 2026 Homework 2：Complete Applications

作業原文：[Assignment 2: Complete Applications](https://hackmd.io/@sysprog/2026-arch-homework2)（本機快照：[`spec.md`](spec.md)）

**截止：2026-11-15 23:59 (GMT+8)**。頁面寫 **2026-10-28 13:00** 會再改規格／繳交方式，在那之前先當暫定。CodeTrial PIN 會在 **10/28 17:00 前** 寄到 `@gs.ncku.edu.tw`。

## 這次在幹嘛（一句話）

把四個程式（HW1 的 minirubik + Quiz1 BFloat16 + Quiz2 binary GCD + Quiz3 定點／位元邏輯）搬到 **沒有 OS、沒有 C 函式庫** 的 RV32I 環境，用 rv32emu 跑；每個都要有 **C 版、手寫組語、micro-test**；再用 CSR 量指令數、手寫組語要能跟 gcc 拚速度／體積；最後用 **CodeTrial 全程錄影口試**（沒錄影整份作業不算）。

## 交什麼

| 項目 | 截止 | 備註 |
| --- | --- | --- |
| GitHub repo（四個程式的 C / 組語 / Makefile / linker / startup / tests） | Nov 15 23:59 | 不要整份 clone rv32emu |
| HackMD 英文筆記 | Nov 15 23:59 | 只貼關鍵片段，連到 pinned commit |
| CodeTrial mock interview 全程錄影 | 頁面 10/28 13:00 才會寫怎麼交 | 沒錄影 = 作業不收 |
| Google 表單 | Nov 15 | https://forms.gle/GyNbSQzNoXdEELdFA |

口試期間用任何 AI／TTS／翻譯幫忙 → **整學期作業 0 分**。

## 四個程式

每個都要：C、手寫 RV32I、完整 micro-test。只能用 `-march=rv32izicsr -mabi=ilp32`。`mul`/`div`/`rem` 和浮點指令都不准；編譯器叫得到的 `__mulsi3`、`memset` 等要自己寫。跟模擬器溝通只准 `write`(64) 和 `exit`(93)。

| # | 來源 | 在做什麼 | RV32I 卡點 |
| --- | --- | --- | --- |
| 1 | HW1 minirubik | 2×2 魔方 solver 從 Ripes 搬到 rv32emu | 換成 `write`/`exit`；**4 KiB stack** |
| 2 | Quiz 1 B | BFloat16 運算（含 mantissa 乘、開方） | 沒有 `mul`，自己做 8-bit×8-bit；binary32 當 `uint32_t` 位元，不要用 `float` 算術 |
| 3 | Quiz 2 A | binary GCD（用 shift／subtract，沒有 divider） | 已經是 RV32I；印十進位不能用除法；可用 ctz／`sltu` 再壓 |
| 4 | Quiz 3 C | `op1`/`op2`/`op3` 位元加減，加上 Q11.20 的 `q_mul` | `q_mul` 要 32×32→64 有號乘法；硬體加減器／時序題不用 port |

Quiz 3 C 的 Part 2–4（adder delay、sequential circuit）不是程式，不用搬。

## 硬規則（評分會卡這裡）

- 沒有 libc、沒有 libgcc、沒有 heap（playground 沒 allocator；真的要動態配置就自己寫 bump allocator）
- 映像載入在 `0x10000`，stack 預設 4 KiB，不夠就改 `linker.ld` 但要量得過
- 測試框架：[micro-test](https://github.com/trmckay/micro-test)，`-D NO_STD`，還要改掉它對 POSIX/`strlen` 的依賴（規格寫得很細）
- 量測用 playground 的 `get_cycles()` / `get_instret()`（不要用 `ticks.c` 那份會被優化掉的寫法）
- rv32emu **沒有 timing model**：`cycle` 和 `instret` 是同一個「執行了幾條 guest 指令」的計數，所以報告裡要講這件事，體積另外用 `size -A` 看 `.text` / `.rodata` / `.data` / `.bss`
- 手寫組語要跟「最快的 gcc」比 cycle、跟「最小的 gcc」比 size；測過的每個 `-O*` 都要 micro-test 全過才算數

## 資料夾

| 路徑 | 內容 |
| --- | --- |
| [`spec.md`](spec.md) | 2026-10-27 09:04 抓的官方規格 |
| [`refs/playground/`](refs/playground/) | [gist](https://gist.github.com/jserv/5f682ac880773cab69e3564f4f20d60a)：`start.S`、`linker.ld`、`perfcounter.S`、ChaCha20 範例 |
| [`refs/micro-test/`](refs/micro-test/) | `utest.c` / `utest.h` |
| [`refs/hackmd/lab2-bare-metal.md`](refs/hackmd/lab2-bare-metal.md) | Lab2 |
| [`refs/hackmd/bf16-sine.md`](refs/hackmd/bf16-sine.md) | 筆記範例（BF16 sine；裡面的浮點指令這次不准用） |
| [`refs/hackmd/line-draw-fixed-point.md`](refs/hackmd/line-draw-fixed-point.md) | 筆記範例（定點畫線） |
| [`refs/rv32emu-files/`](refs/rv32emu-files/) | `ticks.c`、`syscall.md` |
| [`refs/github/codetrial-pr-259.md`](refs/github/codetrial-pr-259.md) | CodeTrial task mode PR（仍 open） |
| [`refs/imgs/`](refs/imgs/) | 規格頁上的 CodeTrial 截圖 |

實作不要寫在這個 refs 裡。交出去的 repo 只該有「從 gist 拷出來、改過相對路徑」的 playground 目錄。

四個程式的工作目錄：

| 資料夾 | 狀態 |
| --- | --- |
| [`01-minirubik/`](01-minirubik/) | 待 port |
| [`02-bf16/`](02-bf16/) | 待寫 |
| [`03-gcd/`](03-gcd/) | host C 框架（`make test`） |
| [`04-logic/`](04-logic/) | 待寫 |

HW1 的 minirubik 在 [`../2026-hw1-minirubik/`](../2026-hw1-minirubik/README.md)。Quiz 題解：

- BFloat16：[`../../weeks/02-quiz1-riscv-intro/quiz/2026-quiz1-sol.md`](../../weeks/02-quiz1-riscv-intro/quiz/2026-quiz1-sol.md)
- binary GCD：[`../../weeks/04-quiz2-instruction-format/quiz/2026-quiz2-sol.md`](../../weeks/04-quiz2-instruction-format/quiz/2026-quiz2-sol.md)（卷面標題是 Two Operands）
- Two Kinds of Logic：[`../../weeks/07-quiz3/quiz/2026-quiz3-sol.md`](../../weeks/07-quiz3/quiz/2026-quiz3-sol.md)

## 本機環境（已搭好、已測過）

模擬器在 [`rv32emu/`](rv32emu/)（**不要交進作業 repo**）。每次新開 terminal：

```bash
cd homework/2026-hw2-baremetal
source env.sh
playground-run -O0
playground-run -O2
```

| 項目 | 本機紀錄（2026-10-27） |
| --- | --- |
| rv32emu | `cab9a11`，`system_defconfig` + `CONFIG_ELF_LOADER=y`，無 SDL／無 Linux boot（這台沒裝 libsdl2、dtc，HW2 用不到） |
| 交叉編譯器 | `riscv64-unknown-elf-gcc` 16.1.0（`tools/riscv/`，HW1 同一套） |
| playground | gist `5f682ac880773cab69e3564f4f20d60a` 在 `rv32emu/tests/system/playground` |
| Makefile 修正 | `riscv64-unknown-elf-ld` 預設是 elf64，已加 `-m elf32lriscv` |

playground `make run`：

| OPT | 結果 | ChaCha20 cycles / instret |
| --- | --- | --- |
| `-O0` | 8 PASSED, 0 FAILED | 6797 / 6797（與 Lab2 手冊相同） |
| `-O2` | 8 PASSED, 0 FAILED | 4322 / 4323 |

之後自己的 ELF：`rv32emu path/to/prog.elf`。

## 建議順序

1. ~~依 Lab2 編 rv32emu……~~ 已完成。
2. 改 micro-test 讓它能在 bare-metal 印東西（這是四個程式的共同地基）。
3. 先 port 最小的：Quiz 2 GCD（[`03-gcd/`](03-gcd/)，host 上 `make test`）。
4. Quiz 1 BF16、Quiz 3 `q_mul`、最後 minirubik（stack 4 KiB 最痛）。
5. 對每個程式做 gcc `-O2/-O3/-Os` vs 手寫組語的表。
6. HackMD；同時準備 Gemini / LiveKit / GitHub OAuth，等 10/28 的 PIN 信。
