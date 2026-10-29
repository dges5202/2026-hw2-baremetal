# RV32I binary GCD.  Follows gcd.c.
#
# No mul / div / rem.  Shifts are logical (srli / sll, never srai).
# Compares are unsigned (bltu / bgeu, never blt / bge): pair 3 has bit 31 set.
# Guest ecalls: write = 64, exit = 93.  No print-integer syscall; decimal is
# repeated subtraction of pow10[].  No stack: leaf functions inline ecall,
# ra is only used by jal/ret.
#
# gcd:
#   a0 = a / return     a1 = b     t0 = count (shared twos)
#   t1, t2 = scratch
#
# main (live across jal gcd / print_u32):
#   s0 = &vals[i]       s1 = remaining pairs
#   s2 = a              s3 = b              s4 = gcd(a, b)
#
# print_u32 (do not touch s0-s4 or ra):
#   a0 = x on entry
#   s5 = remaining x    s6 = &pow10[i]      s7 = powers left (10..1)
#   s8 = started        t0 = digit          t1 = pow10[i]
#   a7 = ecall only

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
2:  call    main
    li      a7, 93
    ecall
3:  j       3b

    .section .text
    .globl  main
    .globl  gcd
    .globl  print_u32

# int main(void)
#   for each pair: s4 = gcd(s2, s3)
#   write "f(" s2 ", " s3 ") = " s4 "\n"
main:
    la      s0, vals                            # s0 = &vals[0]
    la      t0, nvals
    lw      s1, 0(t0)                           # s1 = 6

main_loop:
    beq     s1, x0, main_done                   # no pairs left
    lw      s2, 0(s0)                           # s2 = a
    lw      s3, 4(s0)                           # s3 = b
    mv      a0, s2
    mv      a1, s3
    jal     ra, gcd
    mv      s4, a0                              # s4 = gcd(a, b)

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

    la      a1, nl                              # write "\n"
    li      a2, 1
    li      a0, 1
    li      a7, 64
    ecall

    addi    s0, s0, 8                           # next pair
    addi    s1, s1, -1
    j       main_loop

main_done:
    li      a7, 93
    ecall

# unsigned gcd(unsigned a0, unsigned a1)
gcd:
    beq     a0, x0, return_a                    # a == 0: return b
    beq     a1, x0, return_b                    # b == 0: return a
    li      t0, 0                               # t0 = count

# even_loop: while ((a | b) & 1) == 0
#   a >>= 1, b >>= 1, count++
even_loop:
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    bne     t2, x0, gcd_loop                    # one side odd: stop
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    j       even_loop

# gcd_loop: strip trailing twos, then odd_sub, until a == b
gcd_loop:

# strip_a: while ((a & 1) == 0) a >>= 1
strip_a:
    andi    t1, a0, 1
    bne     t1, x0, strip_b                     # a odd
    srli    a0, a0, 1
    j       strip_a

# strip_b: while ((b & 1) == 0) b >>= 1
strip_b:
    andi    t1, a1, 1
    bne     t1, x0, odd_sub                     # b odd
    srli    a1, a1, 1
    j       strip_b

# odd_sub: both odd
#   if (a > b) a = (a - b) >> 1     unsigned, srli
#   else if (a < b) b = (b - a) >> 1
#   else break
odd_sub:
    beq     a0, a1, gcd_done                    # equal: before sub
    bltu    a0, a1, larger_b                    # a < b
    sub     a0, a0, a1                          # a = a - b
    srli    a0, a0, 1
    j       gcd_loop

larger_b:
    sub     a1, a1, a0                          # b = b - a
    srli    a1, a1, 1
    j       gcd_loop

gcd_done:
    sll     a0, a0, t0                          # put shared twos back
    ret

return_a:
    mv      a0, a1                              # a0 = b
    ret

return_b:
    ret                                         # a0 already holds a

# print_u32(a0 = x)
# Leaf: write one digit via ecall, no jal, no stack.
# For i in 10^9 .. 10^0:
#   digit = how many times pow fits in x (subtract, unsigned)
#   skip while digit == 0 && !started && not last power
#   else started = 1, buf[0] = '0' + digit, write(buf, 1)
# Last power always prints, so 0 becomes "0".
print_u32:
    mv s5, a0                                   # s5 = a0
    la s6, pow10                                # s6 = &pow10[0]
    li s7, 10                                   # s7 = powers left
    mv s8, x0                                   # s8 = started

pu_pow:
    beq s7, x0, pu_done                          #if s7 == 0, goto pu_done
    lw t1, 0(s6)                                # t1 = pow10[i]
    li t0, 0                                    # t0 = digit

pu_sub:
    bltu s5, t1, pu_emit                        # if s5 < t1, goto pu_emit
    sub s5, s5, t1                              # s5 -= t1
    addi t0, t0, 1                              # t0 += 1

    j pu_sub

pu_emit:
    li t2, 1                                    # t2 = 1
    bne t0, x0, pu_write                        # if t0 != 0 goto pu_write
    bne s8, x0, pu_write                        # if s8 != 0 goto pu_write
    beq s7, t2, pu_write                        # if s7 == 1 goto pu_write

    j pu_next

pu_write:
    li s8, 1                                    # s8 = 1
    addi t0, t0, 48                             # t0 += 48
    la a1, buf                                  # a1 = &buf
    sb t0, 0(a1)                                # save t0 to buf    

    # a1 = buf, a2 = 1, a0 = 1, a7 = 64, ecall
                            
    li a2, 1                                    
    li a0, 1
    li a7, 64
    ecall

pu_next:
    addi s6, s6, 4                              # s6 += 4
    addi s7, s7, -1                             # s7 -= 1
    j pu_pow

pu_done:
    ret
