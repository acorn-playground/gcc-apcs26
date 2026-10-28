/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Seven arguments: the last three are passed on the stack (APCS). A frameless
   leaf at -Os once produced "sub a2, sp, #-4294967296" on 64-bit hosts. */
void stack_leaf(unsigned *out, unsigned a, unsigned b, unsigned c,
                unsigned d, unsigned e, unsigned f)
{
    out[0] = a | b | c | d;
    out[1] = e;
    out[2] = f;
}

unsigned stack_frame(unsigned a, unsigned b, unsigned c, unsigned d,
                     unsigned e, unsigned f, unsigned g)
{
    volatile unsigned scratch[300];
    scratch[0] = a; scratch[129] = b; scratch[299] = c;
    return scratch[0] + scratch[129] + scratch[299] + d + e + f + g;
}
