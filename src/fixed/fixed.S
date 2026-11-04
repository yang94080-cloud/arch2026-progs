# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
# a0: a and returned sum; a1: b and carry.
# a2: address of the pass count.
# t0: pass count; t1: carry temporary.
# Leaf function; no stack is needed.
op1_asm:
    li      t0, 0
    beq     a1, zero, .Lfixed_op1_done

.Lfixed_op1_loop:
    # Compute the carry from the original operands before changing a0.
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1

    addi    t0, t0, 1
    bne     a1, zero, .Lfixed_op1_loop

.Lfixed_op1_done:
    sw      t0, 0(a2)
    ret

    .size op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2

# a0: a and result; a1: b. No temporary registers are needed.
op2_asm:
    sub     a0, a0, a1
    ret

    .size op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2

# a0: a and result; a1: b; t0: common bits.
op3_asm:
    and     t0, a0, a1
    xor     a0, a0, a1
    srli    a0, a0, 1
    add     a0, a0, t0
    ret

    .size op3_asm, .-op3_asm
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2

# a0: magnitude of a, then low half of shifted multiplicand
# a1: magnitude of b, shifted right each iteration
# a2: original sign XOR
# a3: high half of shifted multiplicand
# t0: low half of product
# t1: high half of product
# t2, t3: temporary values and carry
q_mul_asm:
    xor     a2, a0, a1

    # Convert both operands to unsigned magnitudes.
    bge     a0, zero, .Lfixed_qmul_a_ready
    neg     a0, a0
.Lfixed_qmul_a_ready:
    bge     a1, zero, .Lfixed_qmul_b_ready
    neg     a1, a1
.Lfixed_qmul_b_ready:

    li      t0, 0
    li      t1, 0
    li      a3, 0

    beq     a0, zero, .Lfixed_qmul_zero
    beq     a1, zero, .Lfixed_qmul_zero

.Lfixed_qmul_loop:
    andi    t2, a1, 1
    beq     t2, zero, .Lfixed_qmul_shift

    # Add the 64-bit multiplicand to the 64-bit product.
    add     t0, t0, a0
    sltu    t3, t0, a0
    add     t1, t1, a3
    add     t1, t1, t3

.Lfixed_qmul_shift:
    # Shift the 64-bit multiplicand left by one.
    srli    t2, a0, 31
    slli    a3, a3, 1
    or      a3, a3, t2
    slli    a0, a0, 1

    srli    a1, a1, 1
    bne     a1, zero, .Lfixed_qmul_loop

    # Apply the sign to the full 64-bit product.
    bge     a2, zero, .Lfixed_qmul_round
    not     t1, t1
    seqz    t2, t0
    neg     t0, t0
    add     t1, t1, t2

.Lfixed_qmul_round:
    # Add 2^19 before discarding the low 20 bits.
    li      t2, 0x80000
    add     t0, t0, t2
    sltu    t3, t0, t2
    add     t1, t1, t3

    # Return the low 32 bits of the product shifted right by 20.
    srli    a0, t0, 20
    slli    t1, t1, 12
    or      a0, a0, t1
    ret

.Lfixed_qmul_zero:
    li      a0, 0
    ret

    .size   q_mul_asm, .-q_mul_asm
