#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Check the built compiler. No RISC OS machine or emulator is needed:
#
#  1. Each case in tests/cases, at each profile below, must compile to exactly
#     the assembly in tests/expected. The expected files come from a build
#     checked on Apple Silicon macOS; a host-dependent compiler bug shows up
#     as a difference.
#  2. No output may contain a 32-bit value wrapped through a 64-bit host
#     integer (such as #-4294967292), the signature of the patched bugs.
#  3. gcc -c must produce an AOF object (chunk file) through the bundled
#     assembler.
#  4. An #include whose case differs from the file's name must be found.
#
#   ./tests/run.sh             check against tests/expected
#   ./tests/run.sh --update    rewrite tests/expected from this build

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${PREFIX:-$ROOT/install}
GCC=$PREFIX/bin/gcc
[ -x "$GCC" ] || { echo "error: $GCC not found; run ./build.sh first" >&2; exit 1; }

UPDATE=0
[ "${1:-}" = --update ] && UPDATE=1

OUT=$ROOT/build/tests
rm -rf "$OUT"
mkdir -p "$OUT" "$ROOT/tests/expected"
cd "$ROOT"

failures=0
fail() { printf 'FAIL %s\n' "$*"; failures=$((failures + 1)); }

COMMON='-mcpu=arm2 -mapcs-26 -mlibscl -fno-builtin -nostdinc'
# name:flags (an application, a module, and a module whose read-only data stays in ROM)
PROFILES='O2:-O2
Os:-Os
module:-Os -mmodule
romlib:-Os -mmodule -mlibrary-static-data-offset'

for src in tests/cases/*.c; do
  case_name=$(basename "$src" .c)
  echo "$PROFILES" | while IFS=: read -r profile flags; do
    tag=$case_name-$profile
    # shellcheck disable=SC2086
    if ! "$GCC" $COMMON $flags -S "$src" -o "$OUT/$tag.s" 2>"$OUT/$tag.err"; then
      fail "$tag: compiler failed"; sed 's/^/    /' "$OUT/$tag.err"; continue
    fi
    if grep -n '#-*42949[0-9][0-9][0-9][0-9][0-9]' "$OUT/$tag.s" >/dev/null; then
      fail "$tag: wrapped 32-bit constant in output"
      grep -n '#-*42949[0-9][0-9][0-9][0-9][0-9]' "$OUT/$tag.s" | sed 's/^/    /'
    fi
    if [ $UPDATE = 1 ]; then
      cp "$OUT/$tag.s" "tests/expected/$tag.s"
    elif ! cmp -s "$OUT/$tag.s" "tests/expected/$tag.s"; then
      fail "$tag: output differs from tests/expected/$tag.s"
      diff -u "tests/expected/$tag.s" "$OUT/$tag.s" | head -20 | sed 's/^/    /'
    else
      printf 'ok   %s\n' "$tag"
    fi
  done
done >"$OUT/results.txt"
cat "$OUT/results.txt"
failures=$(grep -c '^FAIL' "$OUT/results.txt" || true)

# gcc -c through the bundled assembler: an AOF file starts with the chunk
# file identifier &C3CBC6C5, stored little-endian.
if "$GCC" $COMMON -O2 -c tests/cases/arith.c -o "$OUT/arith.o" 2>"$OUT/arith-c.err" &&
   [ "$(od -An -tx1 -N4 "$OUT/arith.o" | tr -d ' \n')" = c5c6cbc3 ]; then
  echo 'ok   gcc -c produces an AOF object'
else
  echo 'FAIL gcc -c did not produce an AOF object'; failures=$((failures + 1))
fi

# An #include spelled with different case from the file, as RISC OS sources
# do (gccsdk-3.4.6-case-insensitive.patch). On a case-insensitive volume, such
# as macOS's default, this passes without the patch.
mkdir -p "$OUT/include/h"
printf '#define CASE_CHECK 42\n' >"$OUT/include/h/editintern"
printf '#include "h/EditIntern"\nint case_check(void) { return CASE_CHECK; }\n' >"$OUT/case.c"
if "$GCC" $COMMON -O2 -I"$OUT/include" -S "$OUT/case.c" -o "$OUT/case.s" 2>"$OUT/case.err" && grep -q '#42' "$OUT/case.s"; then
  echo 'ok   #include finds a file whose name differs in case'
else
  echo 'FAIL #include of a file whose name differs in case'; failures=$((failures + 1))
fi

[ -x "$PREFIX/bin/drlink" ] && echo 'ok   drlink installed' || { echo 'FAIL drlink missing'; failures=$((failures + 1)); }

if [ $UPDATE = 1 ]; then
  echo "Updated tests/expected from this build"
elif [ "$failures" -eq 0 ]; then
  echo "All tests passed"
else
  echo "$failures failure(s)"; exit 1
fi
