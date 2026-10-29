/*
 * Host-side harness for Quiz 2 binary GCD.
 *
 * 你只填 gcd()。測資、main、include 都在下面。
 *   make test
 */

#include <stdio.h>

/* ========== write here ========== */

unsigned gcd(unsigned a, unsigned b)
{
    unsigned count = 0;

    if(a == 0) return b;
    if(b == 0) return a;

    /* even_loop */
    while(a % 2 == 0 && b % 2 == 0)
    {
        a = a >> 1;
        b = b >> 1;
        count ++;
    }
    /* gcd_loop */
    while(a != b)
    {
        while((a & 1) == 0) a = a >> 1;
        while((b & 1) == 0) b = b >> 1;


        if(a > b) a = (a - b) >> 1;
        else if(a < b) b = (b - a) >> 1;
        else break;
    }
        /* odd_sub */

    return a << count;
}

/* ========== tests ========== */

struct case_ {
    unsigned a;
    unsigned b;
    unsigned expect;
};

static const struct case_ tests[] = {
    {1071, 462, 21},
    {4096, 3072, 1024},
    {0xF0000000u, 0x30000000u, 0x30000000u},
    {0x80000001u, 3, 3},
    {0, 91, 91},
    {6, 10, 2},
    {0, 0, 0},
    {91, 0, 91},
    {1, 1, 1},
    {3, 5, 1},
    {8, 12, 4},
    {15, 25, 5},
};

int main(void)
{
    int n = (int) (sizeof tests / sizeof tests[0]);
    int fail = 0;

    for (int i = 0; i < n; i++) {
        unsigned a = tests[i].a;
        unsigned b = tests[i].b;
        unsigned expect = tests[i].expect;
        unsigned got = gcd(a, b);
        unsigned got_swap = gcd(b, a);

        if (got != expect || got_swap != expect) {
            printf("FAIL  gcd(%u, %u)  got %u / swap %u  expect %u\n",
                   a, b, got, got_swap, expect);
            fail++;
        } else {
            printf("PASS  gcd(%u, %u) = %u\n", a, b, got);
        }
    }

    printf("%d passed, %d failed\n", n - fail, fail);
    return fail ? 1 : 0;
}
