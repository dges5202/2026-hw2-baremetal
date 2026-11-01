# RV32I binary GCD.  Follows gcd.c.
#
# ILP32 calling convention (riscv-elf-psABI):
#   args a0-a7, 32-bit return a0, 64-bit return a1:a0
#   caller-saved: ra, t0-t6, a0-a7     (any jal / ecall may clobber these)
#   callee-saved: sp, s0-s11           (callee saves before use, restores before ret)
#   sp 16-byte aligned at every call boundary
#
# No mul / div / rem.  Shifts are logical (srli / srl / sll, never srai).
# Compares are unsigned (bltu / bgeu, never blt / bge): pair 3 has bit 31 set.
# Guest ecalls: write = 64, exit = 93.  No print-integer syscall; decimal is
# repeated subtraction of pow10[].
#
# gcd — leaf, no frame (a / t only):
#   a0 = a / return     a1 = b
#   t0 = count (shared twos)
#   t1 = scratch (a|b; parity of a or of b)
#   t2 = scratch (parity, nibble, (a|b) & mask)
#   t5 = mask width k (16..1), even_loop_skip only
#   t6 = low-ones mask,         even_loop_skip only
#   unused: t3, t4
#
# main — 32-byte frame, saves ra, s0-s4, s9, s10:
#   s0 = &vals[i]       s1 = remaining pairs
#   s2 = a              s3 = b              s4 = gcd(a, b)
#   s9 = cycle delta    s10 = instret delta     (gcd window only)
#   t0, t1 = scratch between calls (cyc_sum / iret_sum)
#
# print_u32 — 16-byte frame, saves s0-s3; leaf wrt jal; live values in s*
# because they must survive ecall:
#   a0 = x on entry
#   s0 = remaining x    s1 = &pow10[i]      s2 = powers left (10..1)
#   s3 = started        t0 = digit          t1 = pow10[i]
#   t2 = 1 (last-power sentinel)
#   a0, a1, a2, a7 = ecall write
#
# print_cycret — 16-byte frame, saves ra (calls print_u32):
#   reads s9, s10 (main's; still live because they are callee-saved)
#
# get_cycles / get_instret — leaf, uint64 in a1:a0, clobber a2 (see perfcounter.S)

    .section .rodata
    .align 2
vals:
    .word 1071, 462
    .word 4096, 3072
    .word 0xF0000000, 0x30000000
    .word 0x80000001, 3
    .word 0, 91
    .word 6, 10
nvals:
    .word 6

lab_a:
    .ascii "f("                                 # 2
lab_b:
    .ascii ", "                                 # 2
lab_c:
    .ascii ") = "                               # 4
nl:
    .ascii "\n"                                 # 1
lab_cyc:
    .ascii "  cyc "                             # 6
lab_iret:
    .ascii "  iret "                            # 7
lab_probe:
    .ascii "probe"                              # 5
lab_tot:
    .ascii "total"                              # 5

    .align 2
pow10:                                          # 10^9 .. 10^0
    .word 1000000000
    .word 100000000
    .word 10000000
    .word 1000000
    .word 100000
    .word 10000
    .word 1000
    .word 100
    .word 10
    .word 1

    .section .bss
    .align 2
buf:
    .space 16                                   # one digit for write
cyc_sum:
    .word 0
iret_sum:
    .word 0

    .section .text._start
    .globl  _start
_start:
    la      sp, __stack_top
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  call    main                                # a0 = exit status
    li      a7, 93
    ecall
3:  j       3b

    .section .text
    .globl  main
    .globl  gcd
    .globl  print_u32

# Window around gcd, same shape as the empty probe:
#   get_cycles; get_instret; <body>; get_instret; get_cycles
# Body is empty for the probe, jal gcd for each pair. Print is outside.
main:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    sw      s3, 12(sp)
    sw      s4, 8(sp)
    sw      s9, 4(sp)
    sw      s10, 0(sp)

    la      s0, vals                            # s0 = &vals[0]
    la      t0, nvals
    lw      s1, 0(t0)                           # s1 = 6

    jal     ra, get_cycles
    mv      s9, a0
    jal     ra, get_instret
    mv      s10, a0
    jal     ra, get_instret
    sub     s10, a0, s10
    jal     ra, get_cycles
    sub     s9, a0, s9

    la      a1, lab_probe
    li      a2, 5
    li      a0, 1
    li      a7, 64
    ecall
    jal     ra, print_cycret

main_loop:
    beq     s1, x0, main_done                   # no pairs left
    lw      s2, 0(s0)                           # s2 = a
    lw      s3, 4(s0)                           # s3 = b

    jal     ra, get_cycles
    mv      s9, a0
    jal     ra, get_instret
    mv      s10, a0
    mv      a0, s2
    mv      a1, s3
    jal     ra, gcd
    mv      s4, a0                              # s4 = gcd(a, b)
    jal     ra, get_instret
    sub     s10, a0, s10
    jal     ra, get_cycles
    sub     s9, a0, s9

    la      t0, cyc_sum
    lw      t1, 0(t0)
    add     t1, t1, s9
    sw      t1, 0(t0)
    la      t0, iret_sum
    lw      t1, 0(t0)
    add     t1, t1, s10
    sw      t1, 0(t0)

    la      a1, lab_a                           # write "f("
    li      a2, 2
    li      a0, 1
    li      a7, 64
    ecall

    mv      a0, s2                              # print a
    jal     ra, print_u32

    la      a1, lab_b                           # write ", "
    li      a2, 2
    li      a0, 1
    li      a7, 64
    ecall

    mv      a0, s3                              # print b
    jal     ra, print_u32

    la      a1, lab_c                           # write ") = "
    li      a2, 4
    li      a0, 1
    li      a7, 64
    ecall

    mv      a0, s4                              # print gcd
    jal     ra, print_u32

    jal     ra, print_cycret

    addi    s0, s0, 8                           # next pair
    addi    s1, s1, -1
    j       main_loop

main_done:
    la      t0, cyc_sum
    lw      s9, 0(t0)
    la      t0, iret_sum
    lw      s10, 0(t0)
    la      a1, lab_tot
    li      a2, 5
    li      a0, 1
    li      a7, 64
    ecall
    jal     ra, print_cycret

    li      a0, 0
    lw      s10, 0(sp)
    lw      s9, 4(sp)
    lw      s4, 8(sp)
    lw      s3, 12(sp)
    lw      s2, 16(sp)
    lw      s1, 20(sp)
    lw      s0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    ret

# print "  cyc <s9>  iret <s10>\n"
print_cycret:
    addi    sp, sp, -16
    sw      ra, 12(sp)
    la      a1, lab_cyc
    li      a2, 6
    li      a0, 1
    li      a7, 64
    ecall
    mv      a0, s9
    jal     ra, print_u32
    la      a1, lab_iret
    li      a2, 7
    li      a0, 1
    li      a7, 64
    ecall
    mv      a0, s10
    jal     ra, print_u32
    la      a1, nl
    li      a2, 1
    li      a0, 1
    li      a7, 64
    ecall
    lw      ra, 12(sp)
    addi    sp, sp, 16
    ret

# unsigned gcd(unsigned a0, unsigned a1)
#
# Fall-through architecture.  Labels are ordered so the common arm does
# not take a jump.  rv32emu counts every insn, taken or not, at cost 1;
# the win is skipping the extra `j` / `mv` on the hot path.
#
#                    gcd
#                     |
#              a==0 / b==0? -- yes --> return_a / return_b
#                     | no
#                 even_loop                 fold ctz(a|b) into t0
#                  /       \
#           nibble!=0     nibble==0
#           (k=1,2,3)     (k>=4)
#         1-bit shortcut  binary 16/8/4/2/1
#                  \       /
#                   strip_a1                first peel of leftover 2s on a
#                     | fall
#          +------> strip_b <--------+      peel leftover 2s on b
#          |          | fall         |
#          |       odd_sub           |      both odd
#          |       /  |   \          |
#          |   a<b  a==b   a>b       |
#          |     |    |      |       |
#          |     |    |      | fall  |
#          |     | gcd_done  |       |
#          |     |  a<<=t0   v       |
#          |     |  ret   strip_a    |      peel 2s on a only (b still odd)
#          |     |           |       |
#          |     |      bne odd_sub  |
#          |     |      (a odd)      |
#          |     |           |       |
#          |     |      j odd_sub    |      cannot fall: larger_b is next
#          |     |                   |
#          |     v                   |
#          |  larger_b --------------+      b=(b-a)>>1, then j (cold)
#          |  b still even after >>1
#          +
#
# Why this order:
#   - a>b is the fall-through subtract (pairs in vals[] mostly land here).
#   - a<b pays bltu + j strip_b; swapping with 3x mv was worse on this emu.
#   - strip_a cannot sit above larger_b without that `j`: falling would
#     subtract the wrong way.
#   - After a>b, b is still odd, so only strip_a runs.  After larger_b,
#     only strip_b.  First entry uses strip_a1 then falls into strip_b
#     so both sides are odd before the first odd_sub.
#   - even_loop_skip, if taken, falls into strip_a1 (no j).  The 1-bit
#     shortcut cannot: it sits above skip, so it `j strip_a1`.
gcd:
    beq     a0, x0, return_a                    # a == 0: return b
    beq     a1, x0, return_b                    # b == 0: return a
    li      t0, 0                               # t0 = count

# even_loop: fold shared twos into t0.  k = ctz(a|b) can be anything
# (pair 2 has k = 28), so a nibble peek then a binary 16/8/4/2/1 walk.
#   already odd          -> strip_a1
#   (a | b) & 0xF != 0   -> k = 1,2,3: 1-bit (shortcut)
#   else                 -> k >= 4: binary 16/8/4/2/1 (skip)
even_loop:
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    bne     t2, x0, strip_a1                    # one side odd: stop

    andi    t2, t1, 0xF                         # t2 = (a | b) & 0xF
    beq     t2, x0, even_loop_skip              # k >= 4: binary

even_loop_shortcut:
    srli    a0, a0, 1                           # a >>= 1
    srli    a1, a1, 1                           # b >>= 1
    addi    t0, t0, 1                           # count++
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    beq     t2, x0, even_loop_shortcut          # still both even
    j       strip_a1

even_loop_skip:
    li      t5, 16                              # t5 = k
    li      t6, 0xFFFF                          # t6 = 16 low ones

even_loop_inner:
    or      t1, a0, a1                          # t1 = a | b
    and     t2, t1, t6                          # t2 = (a | b) & mask
    bne     t2, x0, even_loop_inner1            # low t5 bits not all 0

    srl     a0, a0, t5                          # a >>= k
    srl     a1, a1, t5                          # b >>= k
    add     t0, t0, t5                          # count += k

even_loop_inner1:
    srli    t5, t5, 1                           # k /= 2
    srl     t6, t6, t5                          # mask = low k ones
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    beq     t2, x0, even_loop_inner             # still both even

# strip_* is 1-bit, not the binary mask above.  After odd_sub both sides
# were odd, so a-b is even: at least one factor of two is certain (100%).
# For random odds the next twos thin out: two 2s at 50%, three at 25%,
# each extra two halves.  E[v2(a-b)] = 2, and odd_sub already does the
# guaranteed srli, so the expected leftover here is one shift.  Walking
# 16/8/4/2/1 always pays five tests; that loses when extra is 0 or 1,
# which is the common case.  1-bit wins on the expected value.
#
# First entry: peel leftover twos on both sides, then odd_sub.
# After a > b: only strip_a (b still odd). After larger_b: only strip_b.
strip_a1:
    andi    t1, a0, 1                           # t1 = a & 1
    bne     t1, x0, strip_b                     # a odd
strip_a1_inner:
    srli    a0, a0, 1                           # a >>= 1
    andi    t1, a0, 1                           # t1 = a & 1
    beq     t1, x0, strip_a1_inner              # a still even

gcd_loop:
strip_b:
    andi    t1, a1, 1                           # t1 = b & 1
    bne     t1, x0, odd_sub                     # b odd
strip_b_inner:
    srli    a1, a1, 1                           # b >>= 1
    andi    t1, a1, 1                           # t1 = b & 1
    beq     t1, x0, strip_b_inner               # b still even
                                                # fall into odd_sub

# odd_sub: both odd.  Equal before sub.  Unsigned, srli.
#   a > b: a = (a - b) >> 1, strip_a only
#   a < b: b = (b - a) >> 1, strip_b only
odd_sub:
    beq     a0, a1, gcd_done                    # equal: before sub
    bltu    a0, a1, larger_b                    # a < b
    sub     a0, a0, a1                          # a = a - b
    srli    a0, a0, 1                           # fall into strip_a

strip_a:
    andi    t1, a0, 1                           # t1 = a & 1
    bne     t1, x0, odd_sub                     # a odd
strip_a_inner:
    srli    a0, a0, 1                           # a >>= 1
    andi    t1, a0, 1                           # t1 = a & 1
    beq     t1, x0, strip_a_inner               # a still even
    j       odd_sub                             # do not fall into larger_b

larger_b:
    sub     a1, a1, a0                          # b = b - a
    srli    a1, a1, 1
    j       strip_b

gcd_done:
    sll     a0, a0, t0                          # put shared twos back
    ret

return_a:
    mv      a0, a1                              # a0 = b
    ret

return_b:
    ret                                         # a0 already holds a

# print_u32(a0 = x)
# For i in 10^9 .. 10^0:
#   digit = how many times pow fits in x (subtract, unsigned)
#   skip while digit == 0 && !started && not last power
#   else started = 1, buf[0] = '0' + digit, write(buf, 1)
# Last power always prints, so 0 becomes "0".
print_u32:
    addi    sp, sp, -16
    sw      s0, 0(sp)
    sw      s1, 4(sp)
    sw      s2, 8(sp)
    sw      s3, 12(sp)

    mv      s0, a0                              # s0 = x
    la      s1, pow10                           # s1 = &pow10[0]
    li      s2, 10                              # s2 = powers left
    mv      s3, x0                              # s3 = started

pu_pow:
    beq     s2, x0, pu_done                     # no powers left
    lw      t1, 0(s1)                           # t1 = pow10[i]
    li      t0, 0                               # t0 = digit

pu_sub:
    bltu    s0, t1, pu_emit                     # x < pow
    sub     s0, s0, t1                          # x -= pow
    addi    t0, t0, 1                           # digit++
    j       pu_sub

pu_emit:
    li      t2, 1                               # t2 = 1 (last power)
    bne     t0, x0, pu_write                    # digit != 0
    bne     s3, x0, pu_write                    # already started
    beq     s2, t2, pu_write                    # last power: print 0
    j       pu_next

pu_write:
    li      s3, 1                               # started
    addi    t0, t0, 48                          # '0' + digit
    la      a1, buf                             # a1 = &buf
    sb      t0, 0(a1)                           # buf[0] = ascii
    li      a2, 1                               # a2 = 1
    li      a0, 1                               # fd = stdout
    li      a7, 64                              # write
    ecall

pu_next:
    addi    s1, s1, 4                           # next power
    addi    s2, s2, -1
    j       pu_pow

pu_done:
    lw      s3, 12(sp)
    lw      s2, 8(sp)
    lw      s1, 4(sp)
    lw      s0, 0(sp)
    addi    sp, sp, 16
    ret
