<!-- source: https://hackmd.io/@sysprog/line-draw-fixed-point -->

---
tags: computer-arch
---

# Optimizing 2D Line Drawing on RV32I[M] with Fixed-Point Arithmetic
> contributed by [jserv](https://wiki.csie.ncku.edu.tw/User/jserv)

[rv32emu](https://github.com/sysprog21/rv32emu) ships [`tests/line.c`](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c), a port of Milo Yip's [line drawing samples](https://github.com/miloyip/line). It renders 320 anti-aliased line segments with a signed distance field (SDF) and writes the 512x512 result as a PNG through [svpng](https://github.com/miloyip/svpng). The original program computes in `float`. An RV32IM core has no floating-point unit, so every `float` addition, multiplication, division, and square root becomes a call into a software floating-point routine. The commit "[tests: line: Use fixed-point arithmetic (#107)](https://github.com/sysprog21/rv32emu/commit/033312c2470c)" (January 2023) rewrote the program with 32-bit fixed-point numbers.

This note derives the fixed-point operations that the port relies on, measures both versions on rv32emu, and examines the precision of the result. The measurements expose a defect and a hidden overflow in the upstream port. Its sine and cosine routine is off by up to 0.012, which displaces the outer line segments by up to 3 pixels, and its per-operation saturation checks hide an intermediate dot product that exceeds the Q11.20 range, so they cannot simply be removed. Fixing both brings the image within 2 gray levels of the `float` rendering and cuts the instruction count from 283 million to 199 million at `-O2`, against 1186 million for the soft-float original.

On RV32I, which lacks the M extension, every multiplication of two variables and nearly every division becomes a bit-serial libgcc loop, and the same fixed-point code is barely faster than soft-float: 2054 million against 2253 million instructions. Evaluating the distance incrementally, a digit-by-digit square root, and CORDIC take multiplication out of the hot paths; with two small changes to the PNG encoder, the RV32I build retires 32.6 million instructions, within 7% of RV32IM.

![Reference image rendered with float](https://hackmd.io/_uploads/SJ3_iKhiGg.png)

## How `tests/line.c` draws a line

The program draws five rings of 64 segments around the center of the image. Ring $j$ spans the radii $(j + 0.5)$ to $(j + 1.5)$ times $0.085 \cdot 512$ pixels, so every segment is 43.52 pixels long; its segments have half-width $(j + 1)/2$ and lie $2\pi/64$ apart, starting at the angle $j\pi/64$ ([L205-L220](https://github.com/sysprog21/rv32emu/blob/36d0f29/tests/line.c#L205-L220) of the `float` version):

```c
int main()
{
    memset(img, 255, sizeof(img));
    float cx = W * 0.5f, cy = H * 0.5f;
    for (int j = 0; j < 5; j++) {
        float r1 = fminf(W, H) * (j + 0.5f) * 0.085f;
        float r2 = fminf(W, H) * (j + 1.5f) * 0.085f;
        float t = j * PI / 64.0f, r = (j + 1) * 0.5f;
        for (int i = 1; i <= 64; i++, t += 2.0f * PI / 64.0f) {
            float ct = cosf(t), st = sinf(t);
            lineSDFAABB(cx + r1 * ct, cy - r1 * st, cx + r2 * ct, cy - r2 * st,
                        r);
        }
    }
    svpng(fopen("line.png", "wb"), W, H, img, false);
}
```

Each segment needs one cosine and one sine, and drawing it needs a coverage value for every pixel it touches. Milo Yip's samples cover the two classic ways to rasterize a line: stepping along the line with integer arithmetic, and evaluating a distance for each pixel. `tests/line.c` takes the second, and that choice is what brings floating-point arithmetic into the program.

### Bresenham's algorithm

[Bresenham's algorithm](https://doi.org/10.1147/sj.41.0025) (IBM Systems Journal, 1965) draws a one-pixel-wide line between integer endpoints using only integer additions and comparisons. Consider the first octant, $0 \le dy \le dx$ and $dx > 0$ (coincident endpoints plot a single pixel), with $dx = x_1 - x_0$ and $dy = y_1 - y_0$. The algorithm steps $x$ by one each iteration, so the only decision is whether $y$ also steps. The ideal line passes through

$$
y(x) = y_0 + \frac{dy}{dx}(x - x_0)
$$

After plotting $(x_k, y_k)$ with $x_k = x_0 + k$, the next pixel is $(x_k + 1, y_k + 1)$ if the line at $x_k + 1$ lies above the midpoint $y_k + \tfrac{1}{2}$, and $(x_k + 1, y_k)$ otherwise. Multiplying the test by $2dx > 0$ removes the fraction:

$$
y_0 + \frac{dy}{dx}(k + 1) > y_k + \frac{1}{2} \iff D_k = 2(k + 1)\,dy - 2(y_k - y_0)\,dx - dx > 0
$$

The decision variable is therefore updated with one of two constant increments, $2dy$ or $2dy - 2dx$, instead of recomputed:

$$
D_0 = 2dy - dx, \qquad D_{k+1} = D_k + 2dy - 2dx\,(y_{k+1} - y_k)
$$

Each $y_k$ is the ideal $y$ rounded to the nearest integer, with ties ($D_k = 0$) rounded down:

```c
#include <stdio.h>

/* first octant: 0 <= y1 - y0 <= x1 - x0 */
static void bresenham_octant0(int x0, int y0, int x1, int y1)
{
    int dx = x1 - x0, dy = y1 - y0;
    int d = 2 * dy - dx; /* D_0 */
    for (int x = x0, y = y0; x <= x1; x++) {
        printf("(%d, %d) D = %d\n", x, y, d);
        if (d > 0) {
            y++;
            d -= 2 * dx;
        }
        d += 2 * dy;
    }
}

int main(void)
{
    bresenham_octant0(0, 0, 10, 4);
    return 0;
}
```

```
(0, 0) D = -2
(1, 0) D = 6
(2, 1) D = -6
(3, 1) D = 2
(4, 2) D = -10
(5, 2) D = -2
(6, 2) D = 6
(7, 3) D = -6
(8, 3) D = 2
(9, 4) D = -10
(10, 4) D = -2
```

The red circles in the figure mark the midpoints being tested; the value printed in each pixel is $D_k$:

![Bresenham's algorithm from (0,0) to (10,4)](https://hackmd.io/_uploads/BywF433jzl.png)

The other seven octants follow by symmetry: swap the roles of $x$ and $y$ when $|dy| > |dx|$, and step by $-1$ when an endpoint lies to the left or below. The version in [`line_bresenham.c`](https://github.com/miloyip/line/blob/8bc274cd6054a76b87134258f6b3eecd39cb9725/line_bresenham.c), based on [Rosetta Code](https://rosettacode.org/wiki/Bitmap/Bresenham%27s_line_algorithm#C), folds all eight cases into one loop by keeping a single error term that may advance $x$, $y$, or both in each iteration:

```c
void bresenham(int x0, int y0, int x1, int y1) {
    int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
    int dy = abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
    int err = (dx > dy ? dx : -dy) / 2;

    while (setpixel(x0, y0), x0 != x1 || y0 != y1) {
        int e2 = err;
        if (e2 > -dx) { err -= dy; x0 += sx; }
        if (e2 <  dy) { err += dx; y0 += sy; }
    }
}
```

The comma operator in the `while` condition plots the pixel before testing for the end point, so the last pixel is drawn too. Bresenham lines are cheap but limited to integer endpoints, one-pixel width, and hard, aliased edges; see also the [NIST entry](https://xlinux.nist.gov/dads/HTML/bresenham.html).

### Signed distance fields

The renderer in `tests/line.c` instead treats each segment as a shape with a width and asks, for each pixel, how far its center is from that shape. A signed distance field (SDF) gives, for each point, the distance to the boundary of a shape: negative inside, zero on the boundary, positive outside. A segment of half-width $r$ is a capsule, the set of points within distance $r$ of the segment $\overline{AB}$; its SDF is the distance to the segment minus $r$:

![Capsule SDF](https://hackmd.io/_uploads/BJCdjF2jMx.png)

The closest point of the infinite line through $A$ and $B$ to a point $P$ is $D = A + h(B - A)$. Minimizing $|P - A - h(B - A)|^2$ over $h$ by setting its derivative to zero gives

$$
h = \frac{(P - A) \cdot (B - A)}{|B - A|^2}
$$

Clamping $h$ to $[0, 1]$ moves $D$ to the nearer endpoint when the projection falls outside the segment, as for $P'$ below. The capsule SDF is then

$$
d(P) = |P - A - \operatorname{clamp}(h, 0, 1)\,(B - A)| - r
$$

![Projection onto a segment](https://hackmd.io/_uploads/SJ0ust2jzx.png)

Inigo Quilez lists this and other [2D distance functions](https://iquilezles.org/articles/distfunctions2d/). The `float` version of `tests/line.c` ([L164-L177](https://github.com/sysprog21/rv32emu/blob/36d0f29/tests/line.c#L164-L177)) evaluates it directly:

```c
float capsuleSDF(float px,
                 float py,
                 float ax,
                 float ay,
                 float bx,
                 float by,
                 float r)
{
    float pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay;
    float h = fmaxf(
        fminf((pax * bax + pay * bay) / (bax * bax + bay * bay), 1.0f), 0.0f);
    float dx = pax - bax * h, dy = pay - bay * h;
    return sqrtf(dx * dx + dy * dy) - r;
}
```

### Anti-aliased coverage

One distance sample per pixel suffices for anti-aliasing. Treat the capsule's boundary as locally straight and the pixel as a unit square centered at signed distance $d$ from it. For $|d| \le \tfrac{1}{2}$ the covered fraction of the pixel is $\tfrac{1}{2} - d$, exactly when the edge is parallel to a side of the square and approximately otherwise. The renderer therefore uses

$$
\alpha = \operatorname{clamp}\left(\tfrac{1}{2} - d, 0, 1\right)
$$

as the coverage. Pixels deep inside get $\alpha = 1$, pixels more than half a pixel outside get $\alpha = 0$, and the boundary receives a one-pixel ramp. Each segment is then composited over the image with $p \leftarrow (1 - \alpha)\,p + 255\,\alpha\,c$ for each 8-bit channel value $p$ and color component $c \in [0, 1]$, truncated back to 8 bits; the test draws in black, $c = 0$ ([L180-L186](https://github.com/sysprog21/rv32emu/blob/36d0f29/tests/line.c#L180-L186)):

```c
void alphablend(int x, int y, float alpha, float r, float g, float b)
{
    uint8_t *p = img + (y * W + x) * 3;
    p[0] = (uint8_t) (p[0] * (1 - alpha) + r * alpha * 255);
    p[1] = (uint8_t) (p[1] * (1 - alpha) + g * alpha * 255);
    p[2] = (uint8_t) (p[2] * (1 - alpha) + b * alpha * 255);
}
```

### Bounding boxes

Evaluating the SDF of every segment at every pixel would cost $320 \times 512^2 = 83{,}886{,}080$ evaluations. The capsule lies inside its axis-aligned bounding box (AABB) $[\min(a_x, b_x) - r, \max(a_x, b_x) + r] \times [\min(a_y, b_y) - r, \max(a_y, b_y) + r]$, and coverage is nonzero only within half a pixel of the capsule. A pixel center outside the integer bounds `floor(min - r)` to `ceil(max + r)` lies at least one pixel beyond the box, so $d \ge 1$ and $\alpha = 0$, and only the pixels in those bounds need the SDF ([L189-L203](https://github.com/sysprog21/rv32emu/blob/36d0f29/tests/line.c#L189-L203)):

```c
void lineSDFAABB(float ax, float ay, float bx, float by, float r)
{
    int x0 = (int) floorf(fminf(ax, bx) - r);
    int x1 = (int) ceilf(fmaxf(ax, bx) + r);
    int y0 = (int) floorf(fminf(ay, by) - r);
    int y1 = (int) ceilf(fmaxf(ay, by) + r);
    for (int y = y0; y <= y1; y++) {
        for (int x = x0; x <= x1; x++)
            alphablend(
                x, y,
                fmaxf(fminf(0.5f - capsuleSDF(x, y, ax, ay, bx, by, r), 1.0f),
                      0.0f),
                0.0f, 0.0f, 0.0f);
    }
}
```

![Pixels covered by a capsule and its bounding box](https://hackmd.io/_uploads/BkkYjYniMg.png)

For the 320 segments of the test, the boxes contain 290,248 pixels in total, 289 times fewer evaluations than the full image. A diagonal segment still wastes most of its box, as the figure shows. A fixed-point port therefore has to provide three two-component dot products, a division, a square root, and the blend for each pixel, and a sine, a cosine, and the floor and ceiling of the box bounds for each segment.

## Number formats

### IEEE 754 binary32 in software

[IEEE 754 binary32](https://en.wikipedia.org/wiki/Single-precision_floating-point_format), the format of C's `float` on RISC-V, packs a sign bit $s$, an 8-bit biased exponent $e$, and a 23-bit fraction $f$:

| Sign | Exponent | Fraction |
|---|---|---|
| 1 bit | 8 bits | 23 bits |

For $1 \le e \le 254$ the encoded value is

$$
v = (-1)^s \times (1.f)_2 \times 2^{e - 127}
$$

The leading 1 is implicit (the hidden bit), which gives 24 significant bits. The bias $127 = 2^{8-1} - 1$ centers the exponent range, so $e = 127$ encodes $2^0$. The reserved values $e = 0$ (zero and subnormal numbers) and $e = 255$ (infinities and NaNs) fall outside the formula. The program below decodes `0x3F900000`:

```c
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    uint32_t bits = 0x3F900000; /* 0 01111111 00100000000000000000000 */
    float f;
    memcpy(&f, &bits, sizeof(f));

    printf("sign: %c\n", (bits >> 31) ? '-' : '+');
    printf("exponent: %d\n", (int) ((bits >> 23) & 0xFF) - 127);
    printf("fraction: 0x%06x\n", (unsigned) (bits & 0x7FFFFF));
    printf("hex float: %a\n", f);
    printf("value: %f\n", f);
    return 0;
}
```

```
sign: +
exponent: 0
fraction: 0x100000
hex float: 0x1.2p+0
value: 1.125000
```

The value is $(1.001)_2 \times 2^0 = 1.125$. Copying the bits with `memcpy` avoids reading a `uint32_t` object through a `float *`, which violates the effective type rule (C11 6.5 §7). The [IEEE 754 converter](https://www.h-schmidt.net/FloatConverter/IEEE754.html) by Harald Schmidt shows the same decomposition interactively.

With `-mabi=ilp32` and no F extension, GCC lowers each `float` operation to a call into libgcc's [soft-float routines](https://gcc.gnu.org/onlinedocs/gccint/Soft-float-library-routines.html). Disassembling a loop that repeats `x = x - b` shows `x = x - b` becoming `jal __subsf3`, and likewise `__mulsf3`, `__divsf3`, and a call to newlib's `sqrtf`. Each routine unpacks the IEEE 754 fields, computes on the significands and exponents with integer instructions, then normalizes, rounds, and packs the result.

### Fixed point and the Q format

A fixed-point number stores an integer $A$ and fixes the binary point by convention: the represented value is $a = A \cdot 2^{-n}$ for a constant $n$ chosen at design time. With $n = 3$, the byte `0b01011001` reads as $(01011.001)_2$:

```c
#include <stdint.h>
#include <stdio.h>

int main(void)
{
    uint8_t a = 0x59; /* 0b01011.001: 3 fraction bits */
    printf("integer part: %d\n", a >> 3);
    printf("value: %f\n", (float) a / (1 << 3));
    return 0;
}
```

```
integer part: 11
value: 11.125000
```

Adjacent representable values differ by $2^{-n}$ everywhere in the range, here $2^{-3} = 0.125$. A floating-point number spends 8 bits on an exponent so that its relative precision stays near $2^{-24}$ from $10^{-38}$ to $10^{38}$; a fixed-point number spends every bit on a single scale. When the range of every intermediate value is known in advance, as in a renderer with a fixed image size, that trade gives more precision per bit, and the arithmetic runs on the integer ALU.

The [Q format](https://en.wikipedia.org/wiki/Q_(number_format)) names the split. In the Texas Instruments convention used here, a signed 32-bit Qm.n number has one sign bit, $m$ integer bits, and $n$ fraction bits, so $m + n = 31$:

| Sign | Integer | Fraction |
|---|---|---|
| 1 bit | $m$ bits | $n$ bits |

It represents the range $[-2^m, 2^m - 2^{-n}]$ with resolution $2^{-n}$. An unsigned UQm.n number has no sign bit, so $m + n = 32$. Arm uses a variant in which $m$ counts the sign bit, making the same 32-bit layout Q12.20 instead of Q11.20.

## Fixed-point arithmetic

The port fixes $n$ at compile time as `Q` and stores numbers in `qfixed_t`. In the derivations below, $a = A \cdot 2^{-n}$ and $b = B \cdot 2^{-n}$ are operands, and $C$ is the stored integer of the result. The definitions, excerpted from [`tests/line.c`](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L155-L180):

```c
#define Q (20)
#define Q_PI (1686629713 >> (29 - Q))

/* 32-bit Q notation to specify a fixed point number format. */
typedef int32_t qfixed_t;

/* 64-bit Q format buffer, for handling overflow cases */
typedef int64_t qbuf_t;

/* format convertion: float to Q format */
#define f2Q(x) ((qfixed_t) ((x) * (1 << Q)))

/* format convertion: Q format to float */
#define Q2f(x) (((float) (x)) / (1 << Q))

/* format convertion: Q format to int */
#define Q2I(x) ((int) ((x) >> Q))

/* format convertion: int to Q format */
#define I2Q(x) ((qfixed_t) ((x) << Q))

/* maximum value of Q format */
#define QFMT_MAX 0x7FFFFFFF

/* minimum value of Q format */
#define QFMT_MIN 0x80000000
```

### Conversion

From $a = A \cdot 2^{-n}$, the integer closest to a real value $x$ is $A = \operatorname{round}(x \cdot 2^n)$. The macro `f2Q` computes $x \cdot 2^n$ in `float` and converts it to an integer, which truncates toward zero (C11 6.3.1.4 §1) instead of rounding. `Q_PI` is $\lfloor \pi \cdot 2^{29} \rfloor = 1686629713$ shifted down to $n$ fraction bits. All uses of `f2Q` in the program have constant arguments, which GCC folds at compile time, so no floating-point code survives in the fixed-point build.

### Addition and subtraction

$$
a + b = (A + B) \cdot 2^{-n} \quad\Longrightarrow\quad C = A + B
$$

The scale is unchanged, so addition is a plain integer addition. The only hazard is leaving the range; `q_add` computes the sum in 64 bits and saturates ([L183-L191](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L183-L191)):

```c
static inline qfixed_t q_add(qfixed_t a, qfixed_t b)
{
    qbuf_t tmp = (qbuf_t) a + (qbuf_t) b;
    if (tmp > (qbuf_t) QFMT_MAX)
        return (qfixed_t) QFMT_MAX;
    if (~tmp + 1 >= (qbuf_t) QFMT_MIN)
        return (qfixed_t) QFMT_MIN;
    return (qfixed_t) tmp;
};
```

`QFMT_MIN` is the constant `0x80000000`, whose type is `unsigned int`, so `(qbuf_t) QFMT_MIN` is $+2^{31}$, and `~tmp + 1` is $-tmp$. The second test therefore reads $tmp \le -2^{31}$, and `(qfixed_t) QFMT_MIN` converts $2^{31}$ to `int32_t`, which is implementation-defined (C11 6.3.1.3 §3) and yields $-2^{31}$ under GCC. Comparing against `INT32_MAX` and `INT32_MIN` from `<stdint.h>` would say the same thing directly. Subtraction is written `q_add(a, -b)`; negating `b` overflows only for $B = -2^{31}$.

### Multiplication

$$
a \cdot b = A B \cdot 2^{-2n} = \left(A B \cdot 2^{-n}\right) \cdot 2^{-n} \quad\Longrightarrow\quad C = \operatorname{round}\left(A B \cdot 2^{-n}\right) = \left\lfloor \frac{A B + 2^{n-1}}{2^n} \right\rfloor
$$

The product carries $2n$ fraction bits and up to 63 value bits ($(-2^{31})^2 = 2^{62}$), so it needs a signed 64-bit intermediate; RV32IM obtains the two halves with `mul` and `mulh`. Adding half of the divisor before an arithmetic right shift by $n$, which rounds toward $-\infty$, rounds to nearest with ties toward $+\infty$ ([L194-L208](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L194-L208)):

```c
static inline qfixed_t q_mul(qfixed_t a, qfixed_t b)
{
    qbuf_t tmp = (qbuf_t) a * (qbuf_t) b;

    /* rounding and resize */
    tmp += (qbuf_t) (1 << (Q - 1));
    tmp >>= Q;

    /* check overflow */
    if (tmp > (qbuf_t) QFMT_MAX)
        return (qfixed_t) QFMT_MAX;
    if (tmp * -1 >= (qbuf_t) QFMT_MIN)
        return (qfixed_t) QFMT_MIN;
    return (qfixed_t) tmp;
}
```

Right-shifting a negative signed value is implementation-defined (C11 6.5.7 §5); GCC [documents](https://gcc.gnu.org/onlinedocs/gcc/Integers-implementation.html) it as an arithmetic shift.

### Division

$$
\frac{a}{b} = \frac{A}{B} = \left(\frac{A \cdot 2^n}{B}\right) \cdot 2^{-n} \quad\Longrightarrow\quad C = \operatorname{round}\left(\frac{A \cdot 2^n}{B}\right)
$$

The dividend $A \cdot 2^n$ needs up to $31 + n$ bits. C's integer division truncates toward zero (C11 6.5.5 §6), so adding $|B|/2$ to the magnitude of the dividend before dividing rounds to nearest with ties away from zero. The code approximates $|B|/2$ with `b >> 1`, which rounds toward $-\infty$, so for a negative odd divisor it adds one too many: $a = 2^{-20}$, $b = -3 \cdot 2^{-20}$ gives $-349526$ instead of the nearest $-349525$ ([L211-L220](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L211-L220)):

```c
static inline qfixed_t q_div(qfixed_t a, qfixed_t b)
{
    qbuf_t tmp = (qbuf_t) a << Q;
    if ((tmp >= 0 && b >= 0) || (tmp < 0 && b < 0)) {
        tmp += (b >> 1);
    } else {
        tmp -= (b >> 1);
    }
    return (qfixed_t) (tmp / b);
}
```

RV32IM divides only 32 by 32 bits, so `tmp / b` with a 64-bit dividend becomes a call to libgcc's `__divdi3`; division is the one fixed-point operation that is not much cheaper than its soft-float counterpart. Left-shifting a negative `a` is undefined behavior in C11 (6.5.7 §4); GCC, as an extension, defines it as multiplication by $2^Q$, while `-fsanitize=shift` still reports it. Writing `(qbuf_t) a * (1 << Q)` avoids the question and compiles to the same shift.

### Floor and ceiling

In two's complement, clearing the $n$ fraction bits of $A$ rounds toward $-\infty$ for negative values as well: $-1.25$ is stored as $-1.25 \cdot 2^n$, and clearing its low bits yields $-2 \cdot 2^n$. `q_floor` applies that mask, and `q_ceil` adds one unit when any fraction bit is set ([L223-L236](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L223-L236)):

```c
static inline qfixed_t q_floor(qfixed_t x)
{
    qfixed_t mask = (0xFFFFFFFF >> Q) << Q;
    return x & mask;
}

static inline qfixed_t q_ceil(qfixed_t x)
{
    qfixed_t mask = (0xFFFFFFFF >> Q) << Q;
    qfixed_t delta = x & ~mask;
    x = x & mask;
    return delta ? q_add(x, 1 << Q) : x;
}
```

### Square root

$$
\sqrt{a} = \sqrt{A \cdot 2^{-n}} = \sqrt{A \cdot 2^{n}} \cdot 2^{-n} \quad\Longrightarrow\quad C = \left\lfloor \sqrt{A \cdot 2^n} \right\rfloor
$$

The radicand $A \cdot 2^n$ again needs up to $31 + n$ bits. An early version of the port computed $\lfloor \sqrt{A} \rfloor$ and shifted it left by $n/2$, using $\sqrt{A \cdot 2^n} = \sqrt{A} \cdot 2^{n/2}$. That returns only half as many significant bits as $A$ has, so its relative error grows like $1/\sqrt{A}$: about $10^{-3}$ near 1.0 and 3% near $2^{-10}$ in Q11.20.

The upstream `q_sqrt` normalizes first. It shifts $A$ left by an even amount $2s$ so that bit 30 or bit 29 becomes the leading one, takes the integer square root $r = \lfloor \sqrt{A \cdot 2^{2s}} \rfloor$ bit by bit, and rescales with

$$
\sqrt{A \cdot 2^n} = \sqrt{A \cdot 2^{2s}} \cdot 2^{n/2 - s} \approx r \cdot 2^{n/2 - s}
$$

([L239-L278](https://github.com/sysprog21/rv32emu/blob/v1.2/tests/line.c#L239-L278)):

```c
static inline qfixed_t q_sqrt(qfixed_t x)
{
    if (x <= 0)
        return 0;
    if (x < I2Q(1) + (1 << (Q / 2 - 1)) && x > I2Q(1) - (1 << (Q / 2 - 1)))
        return I2Q(1);

    qfixed_t res = 0;
    qfixed_t bit = 1 << 15;

    /* left shift x as more as possible */
    int offset = 0;
    for (qfixed_t i = x; !(0x40000000 & i); i <<= 1)
        ++offset;
    offset = (offset & ~1);
    x <<= offset;

    /* shift bit to the highest bit 1' in x */
    while (bit > x)
        bit >>= 1;

    for (; bit > 0; bit >>= 1) {
        int tmp = bit + res;

        /* check overflow: 46341^2 > 2^31 - 1, which is the maximun value */
        if (tmp > 46340)
            continue;

        int square = tmp * tmp;
        if (square <= x) {
            res = tmp;
            if (square == x)
                break;
        }
    } /* iter: goto next lower bit to get more precise sqrt value */

    offset >>= 1;
    offset -= (Q >> 1);
    return (offset >= 0) ? res >> offset : res << (-offset);
}
```

Since $A \cdot 2^{2s} \ge 2^{29}$, the root satisfies $r \ge 23170$, and truncating it costs a relative error below $1/23170 \approx 4.3 \times 10^{-5}$, about 15 significant bits. Two further errors come on top: shifting $r$ right when $s > n/2$ quantizes small results to the Q grid ($\sqrt{3 \cdot 2^{-20}}$ keeps only 11 bits, a relative error of $3.5 \times 10^{-4}$), and a shortcut, described next, returns exactly 1.0 near 1.0.

The rescaling uses `Q >> 1`, so the routine is correct only for even $n$. The guard $46340^2 = 2147395600 \le 2^{31} - 1 < 46341^2$ keeps `tmp * tmp` from overflowing. The second `if` returns exactly 1.0 for inputs within $2^{-(n/2+1)}$ of 1.0; it masks the sine and cosine errors of the next section and serves no purpose for the square root itself. The figure includes the digit-by-digit routine of the RV32I section, whose remaining error is the Q20 quantization alone; the narrow spike of the upstream curve at 1.0 is the guard:

![Relative error of the fixed-point square root](https://hackmd.io/_uploads/SyQ9N23oMg.png)

## Sine and cosine

### The angle-sum method

The renderer needs $\sin t$ and $\cos t$ for each segment's angle. `q_sincos` first folds $t$ into a quadrant number and an angle $\theta \in [0, \pi/2]$. It then writes $\theta$ greedily as a sum of the angles $\pi/2^k$, $k = 1, 2, \ldots$, and accumulates the rotation with the angle-addition identities

$$
\begin{aligned}
\cos(\alpha + \beta) &= \cos\alpha \cos\beta - \sin\alpha \sin\beta \\
\sin(\alpha + \beta) &= \sin\alpha \cos\beta + \cos\alpha \sin\beta
\end{aligned}
$$

starting from $(\cos 0, \sin 0) = (1, 0)$. Upstream derives each $\cos(\pi/2^{k+1})$ and $\sin(\pi/2^{k+1})$ from the previous cosine with the half-angle formulas, valid for $0 \le x \le \pi$:

$$
\cos\frac{x}{2} = \sqrt{\frac{1 + \cos x}{2}}, \qquad \sin\frac{x}{2} = \sqrt{\frac{1 - \cos x}{2}}
$$

### Where the upstream recurrence fails

The sine formula is ill-conditioned for small $x$. Since $1 - \cos x \approx x^2/2$, an absolute error $\delta$ in $\cos x$ becomes a relative error of about $2\delta/x^2$ in $1 - \cos x$, a case of [catastrophic cancellation](https://en.wikipedia.org/wiki/Catastrophic_cancellation). The 15-bit `q_sqrt` leaves $\delta$ at a few times $10^{-5}$, while $1 - \cos(\pi/128) \approx 3.0 \times 10^{-4}$. Running the recurrence of `q_sincos` (with the upstream `q_sqrt`) in Q11.20 gives:

```
pi/2^1  cos 0.000000 (0.000000) sin 1.000000 (1.000000)
pi/2^2  cos 0.707092 (0.707107) sin 0.707092 (0.707107)
pi/2^3  cos 0.923859 (0.923880) sin 0.382690 (0.382683)
pi/2^4  cos 0.980774 (0.980785) sin 0.195114 (0.195090)
pi/2^5  cos 0.995178 (0.995185) sin 0.098045 (0.098017)
pi/2^6  cos 0.998779 (0.998795) sin 0.049099 (0.049068)
pi/2^7  cos 0.999664 (0.999699) sin 0.024705 (0.024541)
pi/2^8  cos 1.000000 (0.999925) sin 0.012955 (0.012272)
pi/2^9  cos 1.000000 (0.999981) sin 0.000000 (0.006136)
pi/2^10 cos 1.000000 (0.999995) sin 0.000000 (0.003068)
```

The values in parentheses are exact. The sine of $\pi/256$ is already 5.6% too large, and the guard in `q_sqrt` turns $\cos(\pi/256)$ into exactly 1, so every later term becomes the identity rotation. Any residual angle below $\pi/256$ is silently dropped, and $\pi/512 + \pi/1024 + \cdots \approx \pi/256 \approx 0.0123$ bounds the loss. Over the full circle the measured error reaches 0.0123; without the guard it reaches 0.042. The angles of the test are multiples of $\pi/64$, which would need no small terms, but the program accumulates $t$ from a rounded step, so almost every angle carries a small residual.

### A table of constants

The cure is to stop deriving the constants at run time. There are only 21 of them, and they can be computed once in higher precision. The replacement below stores $\pi/2^k$, $\cos(\pi/2^k)$, and $\sin(\pi/2^k)$ for $k = 2, \ldots, 22$ in Q30 (the folded angle never exceeds $\pi/2$, so the $\pi/2$ entry is unnecessary), performs the rotations with 64-bit products, and rounds once to Q format at the end:

```c
/* Angles pi/2^k with their cosines and sines, all in Q30 */
static const struct {
    int32_t angle, cos, sin;
} rot[] = {
    {843314857, 759250125, 759250125}, /* pi/4 */
    {421657428, 992008094, 410903207}, /* pi/8 */
    {210828714, 1053110176, 209476638},
    {105414357, 1068571464, 105245103},
    {52707179, 1072448455, 52686014},
    {26353589, 1073418433, 26350943},
    {13176795, 1073660973, 13176464},
    {6588397, 1073721611, 6588356},
    {3294199, 1073736771, 3294193},
    {1647099, 1073740561, 1647099},
    {823550, 1073741508, 823550},
    {411775, 1073741745, 411775},
    {205887, 1073741804, 205887},
    {102944, 1073741819, 102944},
    {51472, 1073741823, 51472},
    {25736, 1073741824, 25736},
    {12868, 1073741824, 12868},
    {6434, 1073741824, 6434},
    {3217, 1073741824, 3217},
    {1608, 1073741824, 1608},
    {804, 1073741824, 804},
};

/* Compute sin(t) and cos(t) by summing the angles pi/2^k */
static inline void q_sincos(qfixed_t t, qfixed_t *sin_t, qfixed_t *cos_t)
{
    int region = (t / (Q_PI >> 1)) & 0b11;
    qfixed_t theta = t % (Q_PI >> 1);
    if (region & 0b1)
        theta = (Q_PI >> 1) - theta;

    int64_t r = (int64_t) theta << (30 - Q); /* remaining angle, Q30 */
    int64_t c = 1 << 30, s = 0;              /* (cos, sin), Q30 */
    for (size_t k = 0; k < sizeof(rot) / sizeof(rot[0]); k++) {
        if (r < rot[k].angle)
            continue;
        r -= rot[k].angle;
        int64_t nc = (c * rot[k].cos - s * rot[k].sin + (1 << 29)) >> 30;
        s = (s * rot[k].cos + c * rot[k].sin + (1 << 29)) >> 30;
        c = nc;
    }
    /* back to Q format with rounding */
    *cos_t = (qfixed_t) ((c + (1 << (29 - Q))) >> (30 - Q));
    *sin_t = (qfixed_t) ((s + (1 << (29 - Q))) >> (30 - Q));

    if (region == 0b10 || region == 0b01)
        *cos_t = -*cos_t;
    if (region & 0b10)
        *sin_t = -*sin_t;
}
```

The quadrant handling follows upstream, with `-x` in place of the equivalent `~x + 1`. The function replaces `q_sincos` in `tests/line.c` and relies on its `Q`, `Q_PI`, and `qfixed_t` (`size_t` comes from `<string.h>`, which the file already includes). In Q11.20 its error stays below $1.3 \times 10^{-6}$ (1.33 units in the last place) over $[0, \pi/2]$ and below $2.5 \times 10^{-6}$ over the full circle, where folding the angle adds rounding; the upstream recurrence reaches $10^{-2}$. The figure also shows the CORDIC routine derived in the RV32I section, which needs no multiplication and is more accurate still:

![Error of fixed-point sine and cosine](https://hackmd.io/_uploads/HJxoV3hofe.png)

## Range, precision, and overflow

### The largest usable format

Every intermediate value must fit in $[-2^m, 2^m)$, and the precision is $2^{-n}$ with $m = 31 - n$. The squared segment length $|b - a|^2$ in `capsuleSDF` sets the limit: with segments 43.52 pixels long, $|b - a|^2 \approx 1894$, which fits below $2^{11} = 2048$ but not below $2^{10}$. Q11.20 is therefore the finest format the upstream code can use, and even $n$ is required by `q_sqrt`. A dot product in the same function grows larger still near the bounding-box corners, which matters once saturation is removed, as shown below.

### Too few fraction bits

Too few fraction bits distort the geometry before they affect the coverage. `f2Q(0.085f)` truncates the ring spacing, from $0.0820$ at $n = 8$ to $0.0625$ at $n = 4$, so the segments get shorter. The angle step $2\pi/64$ is computed as `q_mul(I2Q(2), q_div(Q_PI, I2Q(64)))`: at $n = 8$, $\pi/64 \cdot 2^8 = 12.57$ rounds to 13, every step is 3.5% too large, and after 64 steps the segments have rotated by about $0.2$ rad. The crops below, enlarged twice and rendered with the table-driven `q_sincos`, show the right edge of the image: at Q27.4 the inner rings shrink out of the frame, at Q23.8 the rotation error is visible, and from Q19.12 on the geometry settles:

![Right edge of the image at several Q formats](https://hackmd.io/_uploads/By5iEn2sMl.png)

The mean absolute difference from the `float` image, in 8-bit gray levels, measures both effects. With the upstream `q_sincos`, the error stays above 20 gray levels at every precision because the angle error dominates; with the table-driven version it falls to 0.04 at Q11.20, where 4.1% of the pixels differ, each by at most 2 levels:

![Mean pixel error against the float rendering for each Q format](https://hackmd.io/_uploads/rJ7Yot2jzl.png)

At the pixel level, the upstream Q11.20 rendering displaces the outer segments by 2 to 3 pixels. The bottom row of the figure maps the absolute difference from `float` in red; the revised rendering differs by at most 2 gray levels, too faint to see:

![Upstream and revised Q11.20 against float, with difference maps](https://hackmd.io/_uploads/B1mh43njGg.png)

### Overflow and saturation

Going past the range limit is not subtle. In Q9.22 the saturated $|b - a|^2$ corrupts the projection in the SDF and every segment collapses to a dot. The upstream port keeps its saturation checks for this reason. The checks cost instructions on every operation, and since Q11.20 appears to leave enough headroom, removing them is tempting. Removing them leaves 116 stray black pixels at the far corners of the bounding boxes, circled in the right half of the figure. There the dot product $(p - a) \cdot (b - a)$, which grows with how far the pixel lies past $b$ along the segment, exceeds the Q11.20 limit of 2048 and wraps. Its maximum over each ring's boxes rises with the half-width $r$, from 1974 for the innermost ring to 2036 for the third; the two outer rings reach 2060 and 2081 and produce 24 and 92 of the stray pixels. Signed overflow is undefined behavior in C, and the GCC build happens to wrap around.

![Overflow in Q9.22 and in Q11.20 without saturation](https://hackmd.io/_uploads/Sk23432jzg.png)

### The revised port

Computing the two dot products in 64 bits removes that overflow without saturating every operation, because $h$ only needs their ratio. The complete set of changes on top of the table-driven `q_sincos` drops the saturation from `q_add` and `q_mul`, widens the dot products, and deletes the guard in `q_sqrt`, which no longer serves a purpose:

```diff
 static inline qfixed_t q_add(qfixed_t a, qfixed_t b)
 {
-    qbuf_t tmp = (qbuf_t) a + (qbuf_t) b;
-    if (tmp > (qbuf_t) QFMT_MAX)
-        return (qfixed_t) QFMT_MAX;
-    if (~tmp + 1 >= (qbuf_t) QFMT_MIN)
-        return (qfixed_t) QFMT_MIN;
-    return (qfixed_t) tmp;
-};
+    return a + b;
+}
 
 /* multiplication of Q format value */
 static inline qfixed_t q_mul(qfixed_t a, qfixed_t b)
 {
-    qbuf_t tmp = (qbuf_t) a * (qbuf_t) b;
-
-    /* rounding and resize */
-    tmp += (qbuf_t) (1 << (Q - 1));
-    tmp >>= Q;
-
-    /* check overflow */
-    if (tmp > (qbuf_t) QFMT_MAX)
-        return (qfixed_t) QFMT_MAX;
-    if (tmp * -1 >= (qbuf_t) QFMT_MIN)
-        return (qfixed_t) QFMT_MIN;
-    return (qfixed_t) tmp;
+    return (qfixed_t) (((qbuf_t) a * b + (1 << (Q - 1))) >> Q);
 }
@@ static inline qfixed_t q_sqrt(qfixed_t x)
     if (x <= 0)
         return 0;
-    if (x < I2Q(1) + (1 << (Q / 2 - 1)) && x > I2Q(1) - (1 << (Q / 2 - 1)))
-        return I2Q(1);
 
@@ qfixed_t capsuleSDF(qfixed_t px,
-    qfixed_t t0 = q_add(q_mul(pax, bax), q_mul(pay, bay));
-    qfixed_t t1 = q_add(q_mul(bax, bax), q_mul(bay, bay));
-    qfixed_t tmp = min(q_div(t0, t1), I2Q(1));
-    qfixed_t h = max(tmp, 0);
+    /* dot products kept in 64 bits (2Q fraction bits) */
+    qbuf_t t0 = (qbuf_t) pax * bax + (qbuf_t) pay * bay;
+    qbuf_t t1 = (qbuf_t) bax * bax + (qbuf_t) bay * bay;
+    qfixed_t h = t0 <= 0 ? 0 : t0 >= t1 ? I2Q(1) : (qfixed_t) (t0 / (t1 >> Q));
 
     qfixed_t dx = q_add(pax, -q_mul(bax, h));
     qfixed_t dy = q_add(pay, -q_mul(bay, h));
 
-    tmp = q_add(q_mul(dx, dx), q_mul(dy, dy));
+    qfixed_t tmp = q_add(q_mul(dx, dx), q_mul(dy, dy));
```

`t0` and `t1` carry $2n$ fraction bits, so `t0 / (t1 >> Q)` yields $h$ with $n$ fraction bits, and the comparisons perform the clamp to $[0, 1]$ before dividing.

## Instruction counts

### Measuring on rv32emu

All instruction counts and rendered images in this note come from rv32emu tagged [v1.2](https://github.com/sysprog21/rv32emu/releases/tag/v1.2), built with `make defconfig` (interpreter, RV32IMAFC with Zicsr, no JIT, user-mode emulation). Programs are compiled with [xPack GNU RISC-V Embedded GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack) 14.2.0 and its newlib, using `-march=rv32im_zicsr -mabi=ilp32`. RV32I builds use `-march=rv32i_zicsr -mabi=ilp32`, and the F-extension builds, used only as a reference point, `-march=rv32imf_zicsr -mabi=ilp32f`. The emulator counts instructions deterministically, so the host machine does not affect them. The error plots of the integer routines (square root, sine, cosine) were computed on the host; those routines use only fixed-width integer arithmetic, so their results do not depend on the machine.

The RISC-V unprivileged specification defines three counters in [Chapter 8.1, "Zicntr" Extension for Base Counters and Timers](https://github.com/riscv/riscv-isa-manual/releases/tag/20240411) (version 20240411). On RV32 each 64-bit counter is read as two halves:

| Counter | CSR (low/high) | Pseudoinstructions | Meaning |
|---|---|---|---|
| cycle | `0xC00`/`0xC80` | `rdcycle`/`rdcycleh` | clock cycles executed by the hart's core |
| time | `0xC01`/`0xC81` | `rdtime`/`rdtimeh` | wall-clock time |
| instret | `0xC02`/`0xC82` | `rdinstret`/`rdinstreth` | instructions retired by the hart |

rv32emu implements them as follows, in [`src/emulate.c`](https://github.com/sysprog21/rv32emu/blob/v1.2/src/emulate.c#L288-L307):

- `CSR_INSTRET` returns the same variable as `CSR_CYCLE`, and the interpreter advances that variable once per executed instruction (the `cycle++` in the [`RVOP` macro](https://github.com/sysprog21/rv32emu/blob/v1.2/src/emulate.c#L684-L689)). The cycle count therefore equals the instruction count, and the cycles per instruction is exactly 1 by construction.
- In user mode, `rdtime` returns the host's `gettimeofday()` in microseconds ([`update_time()`](https://github.com/sysprog21/rv32emu/blob/v1.2/src/emulate.c#L246-L262)). It measures how fast the emulator runs on the host, not how long the RISC-V program would take on hardware.

Ratios such as cycle/time or cycle/instret thus describe the emulator, not a pipeline, and only the instruction count carries information about the program. The harness below reads `instret` around the original `main()`, which is renamed to `line_main()` at compile time:

```c
#include <stdint.h>
#include <stdio.h>

static uint64_t rdinstret(void)
{
    uint32_t hi, lo, hi2;
    do {
        __asm__ volatile("rdinstreth %0" : "=r"(hi));
        __asm__ volatile("rdinstret %0" : "=r"(lo));
        __asm__ volatile("rdinstreth %0" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t) hi << 32) | lo;
}

int line_main();

int main(void)
{
    uint64_t t0 = rdinstret();
    line_main();
    uint64_t t1 = rdinstret();
    printf("instret %llu\n", (unsigned long long) (t1 - t0));
    return 0;
}
```

Re-reading the high half guards against the low half wrapping between the two reads. The program and the harness are built and run with:

```shell
$ riscv-none-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -Dmain=line_main -c -o line.o line.c
$ riscv-none-elf-gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -o line.elf harness.c line.o -lm
$ build/rv32emu line.elf
```

### Cost per operation

The cost of each operation, measured with loops of 1000 operations at `-O2` (each addition, multiplication, and division depends on the previous result; the square roots take the loop counter) and corrected for the 2-instruction loop overhead:

![Instructions per operation](https://hackmd.io/_uploads/HJ3hH5niMl.png)

Saturating addition and multiplication cost 11 and 14 instructions against 66 and 103 for soft-float; without saturation they are 1 and 8 instructions. Division costs 66 instructions, most of them in `__divdi3`, against 107. `q_sqrt` costs 150 instructions against 554 for newlib's `sqrtf`. The F-extension column shows 3 instructions per operation: one `fsub.s`, `fmul.s`, or `fdiv.s`, plus two `fmv` moves forced by the empty `asm` statement that keeps the loop from being folded. Its square root takes 7: besides `fsqrt.s`, a `fcvt.s.w` of the loop counter and a sign test bracketed by `frflags`/`fsflags`, which GCC emits so that a negative argument still calls `sqrtf` to set `errno`; `-fno-math-errno` removes them and brings the square root to 3 as well.

The loop body is `x = q_mul(x, d)` and so on, with `KEEP(x)` defined as `__asm__ volatile("" : "+r"(x))`; `rdinstret` is the one in the harness above, the `q_*` functions are copied from `tests/line.c`, and the no-saturation variants are the one-line versions from the diff above:

```c
#define N 1000
#define KEEP(x) __asm__ volatile("" : "+r"(x))
#define BENCH(name, T, init, body)                                   \
    do {                                                             \
        T x = init;                                                  \
        uint64_t t0 = rdinstret();                                   \
        for (int i = 1; i <= N; i++) {                               \
            body;                                                    \
            KEEP(x);                                                 \
        }                                                            \
        uint64_t t1 = rdinstret();                                   \
        printf("%-9s %6.1f\n", name, (double) (t1 - t0) / N - base); \
    } while (0)

volatile float vf = 1.0001f;
volatile qfixed_t vq = 1048681; /* 1.0001 in Q20 */

int main(void)
{
    double base = 0;
    {
        int x = 0;
        uint64_t t0 = rdinstret();
        for (int i = 1; i <= N; i++)
            KEEP(x);
        base = (double) (rdinstret() - t0) / N;
    }
    float b = vf;
    qfixed_t d = vq;
    BENCH("fadd", float, 900.0f, x = x - b);
    BENCH("fmul", float, 900.0f, x = x * b);
    BENCH("fdiv", float, 900.0f, x = x / b);
    BENCH("fsqrt", float, 0.0f, x = sqrtf((float) i));
    BENCH("q_add", qfixed_t, I2Q(900), x = q_add(x, -d));
    BENCH("add", qfixed_t, I2Q(900), x = add_nosat(x, -d));
    BENCH("q_mul", qfixed_t, I2Q(900), x = q_mul(x, d));
    BENCH("mul", qfixed_t, I2Q(900), x = mul_nosat(x, d));
    BENCH("q_div", qfixed_t, I2Q(900), x = q_div(x, d));
    BENCH("q_sqrt", qfixed_t, 0, x = q_sqrt(I2Q(i)));
    return 0;
}
```

### The whole program

For the whole program, the revised fixed-point version retires 6.0 times fewer instructions than soft-float at `-O2`, and the upstream version 4.2 times fewer:

![Retired instructions for the whole program](https://hackmd.io/_uploads/r1wYjYnoGg.png)

At `-O0` the upstream fixed-point build is slower than soft-float for a reason unrelated to the arithmetic. `lineSDFAABB` passes `max(min((1 << (Q - 1)) - capsuleSDF(...), I2Q(1)), 0)` to `alphablend`, and the function-like macros `min` and `max` expand their arguments more than once, so `capsuleSDF` runs 640,840 times for the 290,250 pixels in its bounding boxes (the upstream bounds include two pixels more than the `float` ones; the revised port's bounds match them). At `-O2` GCC finds that `capsuleSDF` has no side effects and merges the calls; at `-O0` it does not. Evaluating the SDF once into a local variable brings the upstream `-O0` build from 1427 million down to 808 million instructions, below soft-float's 1285 million, and leaves the `-O2` count unchanged. The `float` original calls the functions `fminf` and `fmaxf` and has no such problem.

`-Ofast` enables `-ffast-math`, which cuts the soft-float count from 1186 million to 767 million instructions; its image differs from the `-O2` image by at most one gray level.

The `float` builds for the F extension retire the fewest instructions, but rv32emu charges one cycle for every instruction. On hardware, floating-point division and square root typically take several cycles each while superscalar cores retire several instructions per cycle, so instruction counts do not determine the cycles a core with an FPU would spend.

## Without the M extension

### What RV32I lacks

The base integer ISA RV32I has no multiply or divide instruction. GCC turns a product of two variables, and a division or remainder by a variable or by most constants that are not powers of two, into a call to libgcc; a product with a constant becomes shifts and additions. The RV32 routines are bit-serial loops. `__mulsi3`, the 32-bit product, iterates once per bit of the second operand up to its highest set bit and adds the shifted multiplicand for each set bit, at 5 or 6 instructions per iteration ([`libgcc/config/riscv/muldi3.S`](https://github.com/gcc-mirror/gcc/blob/releases/gcc-14.2.0/libgcc/config/riscv/muldi3.S#L31-L48)). `__muldi3`, the 64-bit product that `q_mul` needs, multiplies the low words with a shift-add loop of up to 32 iterations and adds the two cross products through `__mulsi3` ([`libgcc/config/riscv/multi3.c`](https://github.com/gcc-mirror/gcc/blob/releases/gcc-14.2.0/libgcc/config/riscv/multi3.c#L35-L86)). Division builds on the shift-and-subtract `__udivsi3`; the 64-bit `__divdi3` is the generic long division of `libgcc2.c`, which calls `__udivsi3`, `__umodsi3`, and `__mulsi3` several times.

The cost therefore depends on the operands. A negative operand sign-extends into an all-ones high word, so its cross product runs the full 32 iterations: `q_mul` costs 276 instructions with positive operands, 474 when the first argument GCC passes to `__muldi3` is negative, 643 when the second is (its low word then also has the top bit set, so the low-word loop runs 32 times), and 839 when both are.

Rebuilding the micro-benchmark with `-march=rv32i_zicsr` shows what that does to fixed point:

![Instructions per call on RV32I](https://hackmd.io/_uploads/SJ6nS53sMx.png)

`q_mul` with positive operands (276) is still cheaper than soft-float `fmul` (380), though not with a negative one, which `capsuleSDF` often has. `q_div` (859) now exceeds `fdiv` (820), and the upstream `q_sqrt`, which squares a trial root in every iteration, costs 1477 instructions against 554 for `sqrtf`. The table-driven `q_sincos` performs up to four 64-bit products per rotation and costs 14,445 instructions per call. For the whole program the advantage of fixed point nearly vanishes: 2214 million instructions for the upstream port and 2054 million for the revised one, against 2253 million for soft-float. Multiplication itself has to leave the hot paths, and the techniques that achieve it also help RV32IM.

### Multiplying by the shorter operand

Shift-add multiplication is cheap when one operand is short, and the caller usually knows which one. `mul_shift_add` is the loop of `__mulsi3` written inline, running over the bits of its second argument. Blending a pixel multiplies the 8-bit channel value by $1 - \alpha$; passing the channel value as the second argument bounds the loop at 8 iterations, while a plain `k * p` leaves the operand order to GCC, which here loops over the 20-bit `k`, and costs 115 instructions per product against 53:

```c
/* a * b by shifts and adds; the loop runs once per bit of b */
static inline uint32_t mul_shift_add(uint32_t a, uint32_t b)
{
    uint32_t acc = 0;
    for (; b; b >>= 1, a <<= 1) {
        if (b & 1)
            acc += a;
    }
    return acc;
}
```

### A square root without multiplication

The digit-by-digit method computes $\lfloor \sqrt{X} \rfloor$ for $X = A \cdot 2^n$ two bits at a time, with additions and comparisons only. Let $X_k$ be the number formed by the leading $2k$ bits of $X$, $r_k = \lfloor \sqrt{X_k} \rfloor$, and $R_k = X_k - r_k^2$, so that $0 \le R_k \le 2r_k$. Appending the next two bits $\delta$ gives $X_{k+1} = 4X_k + \delta$, and the new root is $2r_k$ or $2r_k + 1$. Since

$$
X_{k+1} - (2r_k)^2 = 4R_k + \delta, \qquad (2r_k + 1)^2 \le X_{k+1} \iff 4R_k + \delta \ge 2(2r_k) + 1
$$

each step compares the shifted remainder with $2 \cdot 2r_k + 1$ and subtracts it when it fits. The loop reads `x` as 32 bits, so $X$ spans $32 + n$ bits, the trailing $n$ of them zeros shifted in from below, and $16 + n/2$ steps produce the root. The root stays below $\sqrt{2^{31} \cdot 2^{20}} = 2^{25.5}$, so a completed step leaves $R_k \le 2r_k < 2^{27}$, and the value $4R_k + \delta$ formed before the subtraction stays below $2^{29}$; every intermediate fits in 32 bits:

```c
/* floor(sqrt(x * 2^Q)) by the digit-by-digit method; Q must be even */
static inline qfixed_t q_sqrt(qfixed_t x)
{
    if (x <= 0)
        return 0;
    uint32_t v = (uint32_t) x, root = 0, rem = 0;
    for (int i = 0; i < 16 + Q / 2; i++) {
        rem = (rem << 2) | (v >> 30); /* bring down the next two bits */
        v <<= 2;
        root <<= 1;
        if (rem >= 2 * root + 1) {
            rem -= 2 * root + 1;
            root++;
        }
    }
    return (qfixed_t) root;
}
```

The result is exact, $\lfloor \sqrt{A \cdot 2^n} \rfloor$ for every input (an exhaustive test confirms it for every nonnegative `int32_t` input), where the upstream routine keeps 15 significant bits. It costs 316 instructions on both RV32I and RV32IM. On RV32IM the upstream routine is cheaper (150 instructions), so the choice there trades accuracy for speed; on RV32I the digit-by-digit version is both exact and 4.7 times cheaper.

### Taking multiplication out of the pixel loop

The capsule distance needs two dot products per pixel, but both are affine in the pixel position. With the unit direction $u = (b - a)/|b - a|$ and the unit normal $n = (-u_y, u_x)$, define for a pixel $p$

$$
s(p) = (p - a) \cdot u, \qquad t(p) = (p - a) \cdot n
$$

the position along the segment and the signed distance across it. Stepping one pixel adds a constant:

$$
\begin{aligned}
s(x + 1, y) &= s(x, y) + u_x, & t(x + 1, y) &= t(x, y) - u_y \\
s(x, y + 1) &= s(x, y) + u_y, & t(x, y + 1) &= t(x, y) + u_x
\end{aligned}
$$

which is the same idea as Bresenham's decision variable: replace a product evaluated at every pixel with a running sum. Since $h = s/L$ with $L = |b - a|$, the clamp in the capsule distance splits into three cases. Writing $\rho(p)$ for the unsigned distance to the segment, so that the capsule SDF is $d(p) = \rho(p) - r$:

$$
\rho(p) = \begin{cases}
\sqrt{s^2 + t^2} & s < 0 \\
|t| & 0 \le s \le L \\
\sqrt{(s - L)^2 + t^2} & s > L
\end{cases}
$$

Beside the segment the distance is $|t|$, with no square root at all. In every case $\rho \ge |t|$, $\rho \ge -s$, and $\rho \ge s - L$, so a pixel with $|t| \ge r + \tfrac{1}{2}$, $s \le -(r + \tfrac{1}{2})$, or $s \ge L + r + \tfrac{1}{2}$ has $\alpha = 0$ and is skipped after three comparisons. Only the end caps need a square root. There the offset from the endpoint, $e = -s$ or $e = s - L$, and $|t|$ are both below $r + \tfrac{1}{2} \le 3$, so $e^2 + t^2 < 18$; shifting $e$ and $|t|$ down to $n/2$ fraction bits keeps both factors below $3 \cdot 2^{10}$, at most 12 bits, and the squares become cheap shift-add products.

The setup per segment still multiplies and divides: the squared length in 64 bits, its square root, the two divisions for $u$, and four `q_mul` for the starting values of $s$ and $t$. That is a fixed cost of 320 segments, not of 290,248 pixels. The rounding error of $u_x$ and $u_y$, below $2^{-n}$, accumulates once per step; a box spans at most 51 pixels in each direction, so the accumulated error in $s$ and $t$ stays near $100 \cdot 2^{-20} \approx 10^{-4}$ pixel. The truncation to $n/2$ fraction bits in the caps costs more, up to $\sqrt{2} \cdot 2^{-10} \approx 0.0014$ pixel, which moves a channel value on a white background by at most 0.35 gray level before truncation; values near an integer threshold can still change by one level.

```c
/*
 * Evaluate the capsule distance incrementally: s runs along the segment and
 * t across it, both affine in the pixel position, so stepping one pixel adds
 * a constant and the inner loop needs no multiplication or division.
 */
void lineSDFAABB(qfixed_t ax, qfixed_t ay, qfixed_t bx, qfixed_t by, qfixed_t r)
{
    int x0 = Q2I(q_floor(q_add(min(ax, bx), -r)));
    int x1 = Q2I(q_ceil(q_add(max(ax, bx), r)));
    int y0 = Q2I(q_floor(q_add(min(ay, by), -r)));
    int y1 = Q2I(q_ceil(q_add(max(ay, by), r)));

    /* once per segment: length and unit direction (ux, uy) */
    qfixed_t bax = bx - ax, bay = by - ay;
    qbuf_t len2 = (qbuf_t) bax * bax + (qbuf_t) bay * bay; /* 2Q fraction bits */
    qfixed_t len = q_sqrt((qfixed_t) (len2 >> Q));
    qfixed_t ux = (qfixed_t) ((qbuf_t) bax * (1 << Q) / len);
    qfixed_t uy = (qfixed_t) ((qbuf_t) bay * (1 << Q) / len);

    qfixed_t px = I2Q(x0) - ax, py = I2Q(y0) - ay;
    qfixed_t s_row = q_mul(px, ux) + q_mul(py, uy);
    qfixed_t t_row = q_mul(py, ux) - q_mul(px, uy);
    qfixed_t reach = r + (1 << (Q - 1)); /* coverage is zero beyond r + 1/2 */

    for (int y = y0; y <= y1; y++, s_row += uy, t_row += ux) {
        qfixed_t s = s_row, t = t_row;
        uint8_t *p = img + (y * W + x0) * 3;
        for (int x = x0; x <= x1; x++, s += ux, t -= uy, p += 3) {
            qfixed_t at = t < 0 ? -t : t;
            if (at >= reach || s <= -reach || s >= len + reach)
                continue;
            qfixed_t d = at; /* beside the segment: distance to the line */
            if (s < 0 || s > len) {
                /* in an end cap: distance to the endpoint, in Q/2 to square */
                uint32_t ds = (uint32_t) (s < 0 ? -s : s - len) >> (Q / 2);
                uint32_t dt = (uint32_t) at >> (Q / 2);
                d = q_sqrt(
                    (qfixed_t) (mul_shift_add(ds, ds) + mul_shift_add(dt, dt)));
            }
            qfixed_t alpha = reach - d; /* 1/2 - (d - r) */
            if (alpha <= 0)
                continue;
            if (alpha >= I2Q(1)) {
                p[0] = p[1] = p[2] = 0;
                continue;
            }
            uint32_t k = I2Q(1) - alpha; /* blend toward black */
            p[0] = (uint8_t) (mul_shift_add(k, p[0]) >> Q);
            p[1] = (uint8_t) (mul_shift_add(k, p[1]) >> Q);
            p[2] = (uint8_t) (mul_shift_add(k, p[2]) >> Q);
        }
    }
}
```

The function replaces `capsuleSDF`, `alphablend`, and `lineSDFAABB` of the revised port. Fully covered pixels are set to black without arithmetic, and the partial blend $p \cdot (1 - \alpha)$ keeps the truncation of the upstream `alphablend`. Squaring the length in Q11.20 limits segments to $\sqrt{2048} \approx 45.25$ pixels (the test's are 43.52), and a segment shorter than about $2^{-10} \approx 0.001$ pixel gives a zero length and a division by zero. Like the original, the function does not clip: a box that crosses the image edge writes outside `img`.

### Sine and cosine by CORDIC

[CORDIC](https://doi.org/10.1109/TEC.1959.5222693) (Volder, 1959) also sums rotations, but by the angles $\arctan 2^{-i}$, for which a rotation needs no multiplication. Rotating $(x, y)$ by $\sigma_i \arctan 2^{-i}$ with $\sigma_i = \pm 1$ gives

$$
\begin{pmatrix} x' \\ y' \end{pmatrix} = \cos(\arctan 2^{-i}) \begin{pmatrix} x - \sigma_i\, 2^{-i} y \\ y + \sigma_i\, 2^{-i} x \end{pmatrix}
$$

Without the cosine factor each step is two shifts and two additions. The factors do not depend on the direction of rotation, so their product

$$
K = \prod_{i=0}^{29} \cos(\arctan 2^{-i}) = \prod_{i=0}^{29} \frac{1}{\sqrt{1 + 2^{-2i}}} \approx 0.6072529
$$

is applied once by starting from $(K, 0)$ instead of $(1, 0)$. A third variable $z$ holds the angle still to be rotated, and $\sigma_i$ is its sign. The angles $\arctan 2^{-i}$ sum to $1.7433 > \pi/2$, so every folded angle is reachable, and after 30 steps the remaining angle is below $\arctan 2^{-29} \approx 1.9 \times 10^{-9}$. In exact arithmetic the vector grows from length $K$ toward 1; with truncated shifts the Q30 coordinates exceed 1 by at most 5 units over all angles, and $z$ stays within $\pm \pi/2$, both far inside the 32-bit range. Like the upstream routine, the code assumes $t \ge 0$, which holds for every angle the renderer passes:

```c
/* atan(2^-i) in Q30 */
static const int32_t cordic_atan[30] = {
    843314857, 497837829, 263043837, 133525159, 67021687, 33543516,
    16775851,  8388437,   4194283,   2097149,   1048576,  524288,
    262144,    131072,    65536,     32768,     16384,    8192,
    4096,      2048,      1024,      512,       256,      128,
    64,        32,        16,        8,         4,        2,
};

/* product of cos(atan(2^-i)) for i = 0..29, in Q30 */
#define CORDIC_K 652032874

/* CORDIC in rotation mode: shifts and additions only */
static inline void q_sincos(qfixed_t t, qfixed_t *sin_t, qfixed_t *cos_t)
{
    int region = (t / (Q_PI >> 1)) & 0b11;
    qfixed_t theta = t % (Q_PI >> 1);
    if (region & 0b1)
        theta = (Q_PI >> 1) - theta;

    int32_t x = CORDIC_K, y = 0;  /* (cos, sin), Q30 */
    int32_t z = theta << (30 - Q); /* remaining angle, Q30 */
    for (int i = 0; i < 30; i++) {
        int32_t xs = x >> i, ys = y >> i;
        if (z >= 0) {
            x -= ys;
            y += xs;
            z -= cordic_atan[i];
        } else {
            x += ys;
            y -= xs;
            z += cordic_atan[i];
        }
    }
    *cos_t = (x + (1 << (29 - Q))) >> (30 - Q);
    *sin_t = (y + (1 << (29 - Q))) >> (30 - Q);

    if (region == 0b10 || region == 0b01)
        *cos_t = -*cos_t;
    if (region & 0b10)
        *sin_t = -*sin_t;
}
```

Over every Q11.20 angle in $[0, \pi/2]$ the error stays below 0.52 units in the last place, better than the table's 1.33, and below 1.83 units over the angles the program uses beyond that range. A call costs 385 instructions on RV32I and 324 on RV32IM, against 14,445 and 792 for the table.

### The PNG encoder becomes the bottleneck

With the incremental distance, the digit-by-digit square root, and CORDIC, the drawing takes 14.8 million instructions on RV32I and 12.7 million on RV32IM, while the unchanged svpng encoder takes about 120 million on RV32I. It updates the Adler-32 checksum with two `%` operations per byte, each a call to `__umodsi3` on RV32I. Both sums stay below 65521 before the update, and a byte adds at most 255, so the operands are below $2 \cdot 65521$ and one conditional subtraction replaces the division, saving 33 million instructions on RV32I and 9 million on RV32IM:

```diff
 #define SVPNG_U8ADLER(u)       \
     do {                       \
         SVPNG_U8C(u);          \
-        a = (a + (u)) % 65521; \
-        b = (b + a) % 65521;   \
+        a += (u);              \
+        if (a >= 65521)        \
+            a -= 65521;        \
+        b += a;                \
+        if (b >= 65521)        \
+            b -= 65521;        \
     } while (0)
```

Most of the remaining cost is one `fputc` per byte through newlib's stdio. Collecting the bytes in a static buffer and writing it with a single `fwrite` removes another 69 million instructions. The buffer is sized for the one 512x512 RGB image of the test (789,567 bytes); a general encoder would flush it when full:

```diff
-#define SVPNG_PUT(u) fputc(u, fp)
+static unsigned char pngbuf[1 << 20];
+static size_t pnglen;
+#define SVPNG_PUT(u) (pngbuf[pnglen++] = (unsigned char) (u))
@@ void svpng(FILE *fp, unsigned w, unsigned h, const uint8_t *img, bool alpha)
     SVPNG_BEGIN("IEND", 0);
     SVPNG_END(); /* IEND chunk {} */
+    fwrite(pngbuf, 1, pnglen, fp);
 }
```

Both changes leave the PNG file byte for byte identical:

![Whole-program instructions on RV32I and RV32IM](https://hackmd.io/_uploads/B1RnB92izg.png)

The final RV32I build retires 32.6 million instructions, 69 times fewer than the soft-float original on the same ISA, and only 7% more than the same source on RV32IM (30.4 million). The rendered image differs from the revised port's in 964 pixels by one level, with a mean difference of 0.042 gray levels from the `float` rendering and at most 2 levels. None of the techniques requires the M extension. On RV32IM the incremental distance does nearly all of the work (the square root now runs only in the end caps, and CORDIC saves 0.15 million); it cuts the revised port from 199 million to 108 million instructions.

## Keeping fixed point fast and correct

Every defect in this note was invisible in a casual look at the output: the upstream image looks like the `float` image at a glance, and the overflow without saturation touches 116 pixels out of 262,144. The checks that exposed them are cheap enough to keep.

### Bound every intermediate value

Write down the range of each intermediate before choosing the format, and widen only where a bound exceeds it. In this renderer the bounds dictate the implementation: the projection dot product reaches 2081 and needs 64 bits, $|b - a|^2 \approx 1894$ limits the incremental version to 45.25-pixel segments, and the cap distances squared stay below 18, so they fit in 32 bits after shifting to $n/2$ fraction bits. A range argument also licenses cheaper code: the conditional subtraction in Adler-32 is correct only because both sums stay below $2 \cdot 65521$.

### Bound every rounding error

Each operation adds a known error: half a unit for the rounded `q_mul`, under one unit for a truncation, $k \cdot 2^{-n}$ after $k$ incremental steps. Compare the sum with what the output can show; on a white background, a distance error of $1/255 \approx 0.004$ pixel shifts a channel value by one gray level before truncation, although a smaller error can still cross an integer threshold. The half-angle recurrence failed this budget by orders of magnitude because a subtraction of nearly equal values multiplied its input error. Wider intermediates would shrink that error without removing the amplification, while a formula without the subtraction, here a table or CORDIC, removes it at no extra cost.

### Test unary functions exhaustively

A function of one 32-bit argument has $2^{31}$ nonnegative inputs, few enough to test every one on a workstation. The program below checks the digit-by-digit `q_sqrt` against an exact integer square root for all of them; built with `-fopenmp` it runs in 3 seconds on 64 hardware threads:

```c
#include <math.h>
#include <stdint.h>
#include <stdio.h>

#define Q 20
typedef int32_t qfixed_t;
#include "q_sqrt.h" /* q_sqrt from above */

/* exact floor(sqrt(v)) for v < 2^62 */
static uint64_t isqrt64(uint64_t v)
{
    uint64_t r = (uint64_t) sqrtl((long double) v);
    while (r * r > v)
        r--;
    while ((r + 1) * (r + 1) <= v)
        r++;
    return r;
}

int main(void)
{
    long bad = 0;
#pragma omp parallel for reduction(+ : bad) schedule(static, 1 << 16)
    for (int64_t x = 0; x <= INT32_MAX; x++) {
        uint64_t want = x ? isqrt64((uint64_t) x << Q) : 0;
        if ((uint64_t) q_sqrt((qfixed_t) x) != want)
            bad++;
    }
    printf("inputs 0..2^31-1: %ld mismatches against floor(sqrt(x * 2^%d))\n", bad, Q);
    return bad != 0;
}
```

```
inputs 0..2^31-1: 0 mismatches against floor(sqrt(x * 2^20))
```

A test that cannot fail proves nothing, so the check was also run against a mutant that stops one iteration early; it reports a mismatch for every positive input. The same sweep finds the upstream `q_sqrt` exact for only 3,156,325 of the $2^{31} - 1$ positive inputs, off by up to 1023 units. The angle argument of `q_sincos` is unary too, and the CORDIC error figures above come from all 7.0 million Q11.20 angles in $[0, 2\pi + \pi/8)$, which include every angle the program reaches, not from a sample.

### Compare the whole program with a reference

The `float` program is the specification. Comparing the rendered images pixel by pixel, with the mean and maximum difference and the share of differing pixels, caught the 3-pixel displacement of the upstream port. A unit test of `q_sincos` at hand-picked multiples of $\pi/64$ would have missed it, because those angles happen to be accurate.

### Let the compiler find overflow

The arithmetic uses only fixed-width integers, so the same source compiles on the host with `-fsanitize=undefined`. Run over the whole test, UBSan reports a signed overflow in `q_add` for the build without saturation, at the bounding-box corners described above, and, in that build and in the upstream port alike, a left shift of a negative value in `q_div`. The revised port and the final version run clean. UBSan checks only the executed paths, so it complements the range analysis rather than replacing it.

### Treat instruction counts as a budget

rv32emu counts instructions deterministically, so an exact count can serve as a regression test, and the disassembly shows whether a change brought a libgcc call into a hot loop. Listing the calls in the RV32I build:

```shell
$ riscv-none-elf-objdump -d --no-show-raw-insn line.elf |
      awk '$2 == "<lineSDFAABB>:" {p = 1; next} p && /^$/ {p = 0} p' |
      grep -oE '<__[a-z0-9_]+>' | sort | uniq -c
      2 <__divdi3>
      6 <__muldi3>
```

These are exactly the two divisions and six products of the per-segment setup; the pixel loop calls nothing. The same listing for the revised port shows `capsuleSDF`, called once per pixel, with eight `__muldi3`, one `__mulsi3`, and one `__divdi3`.
