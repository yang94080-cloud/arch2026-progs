# BFloat16 routines: hand-written RV32I.

    .text

# Input: a0 holds the binary32 bits. Output: a0 holds the BF16 bits.
# Clobbers: t0, t1, t2. Leaf function; no stack is needed.
    .globl bf16_from_f32_asm
    .type bf16_from_f32_asm, @function
    .align 2
bf16_from_f32_asm:
    # Move the discarded half up and retain the original high half.
    slli    t0, a0, 16
    srli    a0, a0, 16

    # A clear guard bit means the discarded half is below halfway.
    bge     t0, zero, .Lbf16_f32_done

    # Preserve infinity and NaN before considering an increment.
    slli    t1, a0, 17
    li      t2, 0xFF000000
    bgeu    t1, t2, .Lbf16_f32_done

    # Remove the guard bit; combine remaining bits with retained parity.
    slli    t0, t0, 1
    andi    t1, a0, 1
    or      t0, t0, t1
    beq     t0, zero, .Lbf16_f32_done

    addi    a0, a0, 1

.Lbf16_f32_done:
    ret

    .size bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl bf16_mul_asm
    .type bf16_mul_asm, @function
    .align 2

# a0, a1: inputs; a0: result.
# t0: sign; t1, t2: exponents; t3, t4: significands.
# t5: scratch; t6: product. Leaf function; no stack is needed.
bf16_mul_asm:
    # Extract the product sign, fractions, and exponents.
    xor     t0, a0, a1
    li      t5, 0x8000
    and     t0, t0, t5

    andi    t3, a0, 0x7F
    andi    t4, a1, 0x7F
    srli    t1, a0, 7
    andi    t1, t1, 0xFF
    srli    t2, a1, 7
    andi    t2, t2, 0xFF

    # Examine a before b, as required by the contract.
    li      t5, 255
    beq     t1, t5, .Lbf16_mul_special_a
    beq     t2, t5, .Lbf16_mul_special_b

    # Ignore the sign bit when checking for zero.
    slli    t5, a0, 17
    beq     t5, zero, .Lbf16_mul_zero
    slli    t5, a1, 17
    beq     t5, zero, .Lbf16_mul_zero

    # Normalize a denormal; otherwise restore its implicit one.
    bne     t1, zero, .Lbf16_mul_hidden_a
    li      t1, 1

.Lbf16_mul_normalize_a:
    slli    t3, t3, 1
    addi    t1, t1, -1
    andi    t5, t3, 0x80
    beq     t5, zero, .Lbf16_mul_normalize_a
    j       .Lbf16_mul_check_b

.Lbf16_mul_hidden_a:
    ori     t3, t3, 0x80

.Lbf16_mul_check_b:
    bne     t2, zero, .Lbf16_mul_hidden_b
    li      t2, 1

.Lbf16_mul_normalize_b:
    slli    t4, t4, 1
    addi    t2, t2, -1
    andi    t5, t4, 0x80
    beq     t5, zero, .Lbf16_mul_normalize_b
    j       .Lbf16_mul_product

.Lbf16_mul_hidden_b:
    ori     t4, t4, 0x80

.Lbf16_mul_product:
    # Multiply the two 8-bit significands using shifts and additions.
    li      t6, 0

.Lbf16_mul_bits:
    andi    t5, t4, 1
    beq     t5, zero, .Lbf16_mul_skip_add
    add     t6, t6, t3

.Lbf16_mul_skip_add:
    slli    t3, t3, 1
    srli    t4, t4, 1
    bne     t4, zero, .Lbf16_mul_bits

    # Combine the biased exponents.
    add     t1, t1, t2
    addi    t1, t1, -127

    # Renormalize a significand product of at least two.
    li      t5, 0x8000
    bltu    t6, t5, .Lbf16_mul_fraction
    srli    t6, t6, 1
    addi    t1, t1, 1

.Lbf16_mul_fraction:
    srli    t6, t6, 7
    andi    t6, t6, 0x7F

    li      t5, 255
    bge     t1, t5, .Lbf16_mul_inf
    bge     zero, t1, .Lbf16_mul_underflow

    slli    t1, t1, 7
    or      a0, t0, t1
    or      a0, a0, t6
    ret

.Lbf16_mul_underflow:
    # Match the contract's fraction-only underflow behavior.
    li      t5, -6
    blt     t1, t5, .Lbf16_mul_zero
    li      t5, 1
    sub     t5, t5, t1
    srl     t6, t6, t5
    or      a0, t0, t6
    ret

.Lbf16_mul_special_a:
    bne     t3, zero, .Lbf16_mul_return_a
    slli    t5, a1, 17
    beq     t5, zero, .Lbf16_mul_nan
    j       .Lbf16_mul_inf

.Lbf16_mul_special_b:
    bne     t4, zero, .Lbf16_mul_return_b
    slli    t5, a0, 17
    beq     t5, zero, .Lbf16_mul_nan
    j       .Lbf16_mul_inf

.Lbf16_mul_zero:
    mv      a0, t0
    ret

.Lbf16_mul_inf:
    li      a0, 0x7F80
    or      a0, a0, t0
    ret

.Lbf16_mul_nan:
    li      a0, 0x7FC0
    ret

.Lbf16_mul_return_b:
    mv      a0, a1

.Lbf16_mul_return_a:
    ret

    .size bf16_mul_asm, .-bf16_mul_asm

    .globl bf16_sqrt_asm
    .type bf16_sqrt_asm, @function
    .align 2
# a0: input and result.
# t0: exponent; t1: fraction and scaled significand.
# t2: result exponent bits; t3: remainder; t4: root accumulator.
# t5: power of four; t6: scratch and trial.
# Leaf function; no stack is needed.
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xFF
    andi    t1, a0, 0x7F

    # Preserve NaNs and positive infinity.
    li      t6, 255
    beq     t0, t6, .Lbf16_sqrt_special

    # Both signs of zero produce positive zero.
    slli    t6, a0, 17
    beq     t6, zero, .Lbf16_sqrt_zero

    # Negative nonzero values produce NaN.
    srli    t6, a0, 15
    bne     t6, zero, .Lbf16_sqrt_nan

    # Positive denormals produce zero under this contract.
    beq     t0, zero, .Lbf16_sqrt_zero

    ori     t1, t1, 0x80

    # An even stored exponent means an odd unbiased exponent.
    andi    t6, t0, 1
    bne     t6, zero, .Lbf16_sqrt_prepare
    slli    t1, t1, 1

.Lbf16_sqrt_prepare:
    # Prepare the result exponent.
    addi    t2, t0, 127
    srli    t2, t2, 1
    slli    t2, t2, 7

    # N = 128 * (mantissa + 1) - 1.
    addi    t3, t1, 1
    slli    t3, t3, 7
    addi    t3, t3, -1

    li      t4, 0
    li      t5, 0x4000

.Lbf16_sqrt_bits:
    # Form the trial before shifting the root accumulator.
    add     t6, t4, t5
    srli    t4, t4, 1
    bltu    t3, t6, .Lbf16_sqrt_next

    sub     t3, t3, t6
    add     t4, t4, t5

.Lbf16_sqrt_next:
    srli    t5, t5, 2
    bne     t5, zero, .Lbf16_sqrt_bits

    andi    t4, t4, 0x7F
    or      a0, t2, t4
    ret

.Lbf16_sqrt_special:
    bne     t1, zero, .Lbf16_sqrt_return
    srli    t6, a0, 15
    beq     t6, zero, .Lbf16_sqrt_return

.Lbf16_sqrt_nan:
    li      a0, 0x7FC0
    ret

.Lbf16_sqrt_zero:
    li      a0, 0

.Lbf16_sqrt_return:
    ret

    .size bf16_sqrt_asm, .-bf16_sqrt_asm
