# Quiz 2 A：binary GCD

先在 **host** 上把演算法寫對，再搬去 rv32emu。

```bash
make test
```

你只要改 [`gcd.c`](gcd.c) 裡的 `gcd()`（`even_loop` / `gcd_loop` / `odd_sub` 標好了）。測資含 Quiz 2 那六組，加上 0、互質、兩邊交換。`main` 會再測一次 `gcd(b, a)`。

手寫組語在 [`gcd.S`](gcd.S)：註解和標籤對齊上面的 C，你填指令。`_start` 已經寫好。

```bash
source ../env.sh
make run-asm
```

期望輸出跟 Quiz 一樣：

```
f(1071, 462) = 21
f(4096, 3072) = 1024
f(4026531840, 805306368) = 805306368
f(2147483649, 3) = 3
f(0, 91) = 91
f(6, 10) = 2
```

之後才做 micro-test、ctz / `sltu` 優化。
