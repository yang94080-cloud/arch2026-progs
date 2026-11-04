#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0u)
        return b;
    if (b == 0u)
        return a;

    unsigned shared = 0;

    /* Remove and remember the common factors of two. */
    while (((a | b) & 1u) == 0u) {
        a >>= 1;
        b >>= 1;
        shared++;
    }

    /* Keep a odd throughout the main loop. */
    while ((a & 1u) == 0u)
        a >>= 1;

    do {
        while ((b & 1u) == 0u)
            b >>= 1;

        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        b -= a;
    } while (b != 0u);

    return a << shared;
}
