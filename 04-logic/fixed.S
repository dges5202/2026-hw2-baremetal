# op1_asm, op2_asm, op3_asm, q_mul_asm: hand-written RV32I leaves.
#
# The harness calls these symbols. Fill in each body yourself.
# A leaf does not jal, so ra stays live and a final ret returns.
# Use a0-a7 and t0-t6 only. s0-s11 and sp stay untouched.
#
#   op1_asm(a, b, n)   a0, a1, a2 -> a0    sw the pass count to 0(a2)
#   op2_asm(a, b)      a0, a1 -> a0
#   op3_asm(a, b)      a0, a1 -> a0
#   q_mul_asm(a, b)    a0, a1 -> a0        64-bit product in a register pair
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # a0 = a          argument / return
    # a1 = b
    # a2 = &n         sw the pass count to 0(a2) before reusing a2
    # t0-t6           scratch
    li      t0, 0     # 0 = count
    beqz    a1, op1_loop_skip
                                  
op1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bnez    a1, op1_loop

op1_loop_skip:
    sw      t0, 0(a2)
    ret
    .size   op1_asm, .-op1_asm


    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    # a0 = a          argument / return
    # a1 = b
    # t0-t6           scratch
    sub     a0, a0, a1
    ret


    .size   op2_asm, .-op2_asm


    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # a0 = a          argument / return
    # a1 = b
    # t0-t6           scratch
    andi    t0, a0, 1
    andi    t1, a1, 1
    and     t2, t0, t1
    srli    a0, a0, 1
    srli    a1, a1, 1
    add     a0, a0, a1
    add     a0, a0, t2
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # a0 = a          argument / return (low 32 bits of the Q11.20 product)
    # a1 = b
    # t0 = product low
    # t1 = product high
    # t2-t6           scratch
    srli    t0, a0, 31
    srli    t1, a1, 31
    xor     t6, t0, t1
    beqz    t0, q_mul_skip1
    sub     a0, x0, a0
q_mul_skip1:
    beqz    t1, q_mul_skip2
    sub     a1, x0, a1

q_mul_skip2:
    li      t0, 0
    li      t1, 0
    li      t4, 0
q_mul_loop:
    andi    t2, a1, 1
    beqz    t2, q_mul_loop_skip
    add     t0, t0, a0
    sltu    t3, t0, a0
    add     t1, t1, t4
    add     t1, t1, t3
q_mul_loop_skip:
    srli    t3, a0, 31
    slli    a0, a0, 1
    slli    t4, t4, 1
    or      t4, t4, t3

    srli    a1, a1, 1
    bnez    a1, q_mul_loop


    beqz    t6, q_mul_round
    sub     t0, x0, t0
    sltu    t3, x0, t0
    sub     t1, x0, t1
    sub     t1, t1, t3
q_mul_round:
    li      t3, 1
    slli    t3, t3, 19
    add     t0, t0, t3
    sltu    t4, t0, t3
    add     t1, t1, t4
    srli    t0, t0, 20
    slli    t1, t1, 12
    or      a0, t0, t1
    ret
    .size   q_mul_asm, .-q_mul_asm
