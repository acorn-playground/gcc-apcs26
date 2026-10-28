/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Variadic functions and switch tables exercise the code generator paths
   that crashed with variadic callback casts on ARM64 hosts. */
typedef __builtin_va_list va_list;

int sum(int n, ...)
{
    va_list ap;
    int total = 0;
    __builtin_va_start(ap, n);
    while (n-- > 0)
        total += __builtin_va_arg(ap, int);
    __builtin_va_end(ap);
    return total;
}

const char *name(int k)
{
    switch (k) {
    case 0: return "zero";
    case 1: return "one";
    case 2: return "two";
    case 3: return "three";
    case 4: return "four";
    case 5: return "five";
    default: return "many";
    }
}

struct big { int w[16]; };

void copy(struct big *to, const struct big *from)
{
    *to = *from;
}

/* Variadic and not a leaf: needs a frame and pushes its anonymous
   arguments ("pretend" arguments), both negated offsets in the prologue. */
extern int consume(int, const int *);

int forward(int n, ...)
{
    va_list ap;
    int copy[4], i;
    __builtin_va_start(ap, n);
    for (i = 0; i < n && i < 4; i++)
        copy[i] = __builtin_va_arg(ap, int);
    __builtin_va_end(ap);
    return consume(n, copy);
}
