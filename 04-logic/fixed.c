#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    uint32_t c;
    int count = 0;

    while (b != 0) {
        c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count++;
    }   
    *n = count;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    if (a >= b)
        return a - b;
    return -(b - a);
}

uint32_t op3(uint32_t a, uint32_t b)
{
    int a_last_bit = a & 1;
    int b_last_bit = b & 1;
    a >>= 1;
    b >>= 1;
    return a + b + (a_last_bit & b_last_bit);
}

int32_t q_mul(int32_t a, int32_t b)
{
    int64_t a_64 = a;
    int64_t b_64 = b;
    int64_t result = a_64 * b_64;
    return (result + ((int64_t) 1 << 19)) >> 20;
}
