#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;

    while (b != 0u) {
        uint32_t carry = (a & b) << 1;
        a = a ^ b;
        b = carry;
        passes++;
    }

    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    /* Compute the floor average without overflowing the intermediate sum. */
    return (a & b) + ((a ^ b) >> 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    if (a == 0 || b == 0)
        return 0;

    uint32_t magnitude_a = (uint32_t) a;
    uint32_t magnitude_b = (uint32_t) b;

    if (a < 0)
        magnitude_a = 0u - magnitude_a;
    if (b < 0)
        magnitude_b = 0u - magnitude_b;

    uint32_t low = 0;
    uint32_t high = 0;
    uint32_t shifted_low = magnitude_a;
    uint32_t shifted_high = 0;

    while (magnitude_b != 0u) {
        if ((magnitude_b & 1u) != 0u) {
            uint32_t previous = low;
            low += shifted_low;
            high += shifted_high + (uint32_t) (low < previous);
        }

        shifted_high = (shifted_high << 1) | (shifted_low >> 31);
        shifted_low <<= 1;
        magnitude_b >>= 1;
    }

    /* Negate the full register pair when the product is negative. */
    if ((a < 0) != (b < 0)) {
        high = ~high + (uint32_t) (low == 0u);
        low = 0u - low;
    }

    /* Add the rounding bias, including its carry into the high half. */
    const uint32_t bias = 1u << (Q - 1);
    high += (uint32_t) (low > UINT32_MAX - bias);
    low += bias;
    uint32_t bits = (low >> Q) | (high << (32 - Q));

    if (bits <= 0x7FFFFFFFu)
        return (int32_t) bits;

    return -1 - (int32_t) (~bits);
}
