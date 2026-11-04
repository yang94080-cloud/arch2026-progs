#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exponent = (f32bits >> 23) & 0xFFu;

    /* Preserve the top half of infinity and NaN as the contract requires. */
    if (exponent == 0xFFu)
        return (uint16_t) (f32bits >> 16);

    /* The lowest retained bit resolves halfway cases toward even. */
    uint32_t lowest_kept_bit = (f32bits >> 16) & 1u;
    return (uint16_t) ((f32bits + 0x7FFFu + lowest_kept_bit) >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;
    uint32_t mant_a = a & 0x7Fu, mant_b = b & 0x7Fu;
    int exp_a = (int) ((a >> 7) & 0xFFu);
    int exp_b = (int) ((b >> 7) & 0xFFu);

    /* The contract examines a before b, including NaN handling. */
    if (exp_a == 255) {
        if (mant_a != 0u)
            return a;
        if ((b & 0x7FFFu) == 0u)
            return 0x7FC0u;
        return (uint16_t) (sign | 0x7F80u);
    }

    if (exp_b == 255) {
        if (mant_b != 0u)
            return b;
        if ((a & 0x7FFFu) == 0u)
            return 0x7FC0u;
        return (uint16_t) (sign | 0x7F80u);
    }

    if ((a & 0x7FFFu) == 0u || (b & 0x7FFFu) == 0u)
        return (uint16_t) sign;

    /* Normalize nonzero denormals; normals have an implicit leading one. */
    if (exp_a == 0) {
        exp_a = 1;
        while (mant_a < 0x80u) {
            mant_a <<= 1;
            exp_a--;
        }
    } else {
        mant_a |= 0x80u;
    }

    if (exp_b == 0) {
        exp_b = 1;
        while (mant_b < 0x80u) {
            mant_b <<= 1;
            exp_b--;
        }
    } else {
        mant_b |= 0x80u;
    }

    uint32_t product = mant_a * mant_b;
    int exponent = exp_a + exp_b - 127;

    /* A significand product of at least two needs one right shift. */
    if (product >= 0x8000u) {
        product >>= 1;
        exponent++;
    }

    uint32_t fraction = (product >> 7) & 0x7Fu;

    if (exponent >= 255)
        return (uint16_t) (sign | 0x7F80u);

    if (exponent <= 0) {
        if (exponent < -6)
            return (uint16_t) sign;

        /* Preserve the contract's fraction-only underflow behavior. */
        fraction >>= (unsigned) (1 - exponent);
        return (uint16_t) (sign | fraction);
    }

    return (uint16_t) (sign | ((uint32_t) exponent << 7) | fraction);
}

uint16_t bf16_sqrt(uint16_t a)
{
    uint32_t exponent = (a >> 7) & 0xFFu;
    uint32_t fraction = a & 0x7Fu;

    /* Preserve NaNs and positive infinity; negative infinity gives NaN. */
    if (exponent == 255u) {
        if (fraction != 0u)
            return a;
        return (a & 0x8000u) ? 0x7FC0u : a;
    }

    /* Both signs of zero give positive zero. */
    if ((a & 0x7FFFu) == 0u)
        return 0;

    if ((a & 0x8000u) != 0u)
        return 0x7FC0u;

    /* Positive denormals give zero under this contract. */
    if (exponent == 0u)
        return 0;

    uint32_t mantissa = 0x80u | fraction;

    /* An even stored exponent means an odd unbiased exponent. */
    if ((exponent & 1u) == 0u)
        mantissa <<= 1;

    uint32_t result_exp = (exponent + 127u) >> 1;

    /* Find the largest mid satisfying the specified truncated comparison. */
    uint32_t low = 90u, high = 256u, root = 0;

    while (low <= high) {
        uint32_t mid = (low + high) >> 1;

        if (((mid * mid) >> 7) <= mantissa) {
            root = mid;
            low = mid + 1u;
        } else {
            high = mid - 1u;
        }
    }

    return (uint16_t) ((result_exp << 7) | (root & 0x7Fu));
}
