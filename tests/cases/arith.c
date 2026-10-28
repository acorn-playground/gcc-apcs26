/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Division and floating point become library calls on ARM2; recursion
   exercises stack-limit checking. */
int quot(int a, int b) { return a / b + a % b; }
unsigned uquot(unsigned a, unsigned b) { return a / b; }
double area(double r) { return 3.14159265358979 * r * r; }
float scale(float x, int n) { return x * (float)n; }
long fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
static const char message[] = "read-only data";
const char *greeting(void) { return message; }
