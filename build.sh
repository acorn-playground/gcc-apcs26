#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build GCCSDK 3.4.6 (arm-riscos-aof: ARM2, APCS-26) and Drlink from the
# sources in this repository. Nothing is downloaded.
#
#   ./build.sh            build into ./install
#   PREFIX=/opt/apcs26 ./build.sh
#   JOBS=8 ./build.sh
#
# Output: $PREFIX/bin/gcc and $PREFIX/bin/drlink. Logs are in build/logs.

set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=${BUILD_DIR:-$ROOT/build}
PREFIX=${PREFIX:-$ROOT/install}
JOBS=${JOBS:-4}
LOGS=$BUILD/logs
HOST=$BUILD/host
REVISION=f79cb59110e2d13566678d923dadba0f97a1321d

case $PREFIX in /*) ;; *) PREFIX=$(pwd)/$PREFIX ;; esac

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Run a command with its output in a log; show the log's tail if it fails.
run() {
  log=$1; shift
  if ! "$@" >>"$LOGS/$log" 2>&1; then
    printf 'error: %s failed; last lines of %s:\n' "$*" "$LOGS/$log" >&2
    tail -n 30 "$LOGS/$log" >&2
    exit 1
  fi
}

for tool in make patch tar; do
  command -v $tool >/dev/null 2>&1 || die "$tool is required"
done
CC=${CC:-$(command -v clang || command -v cc || true)}
[ -n "$CC" ] || die "a C compiler (clang or cc) is required"

# Verify every source archive and patch before touching anything.
if command -v sha256sum >/dev/null 2>&1; then SUM='sha256sum'; else SUM='shasum -a 256'; fi
say "Checking source hashes"
(cd "$ROOT" && $SUM -c SHA256SUMS >/dev/null) || die "SHA256SUMS does not match; the sources have changed"

mkdir -p "$LOGS" "$HOST"
PATH=$HOST/bin:$PATH
export PATH

# GNU M4 and Autoconf, pinned, built into build/host. The compiler's configure
# scripts are regenerated with this Autoconf (the 2004 ones don't know ARM64).
for pkg in m4-1.4.20 autoconf-2.72; do
  if [ ! -f "$BUILD/$pkg/.built" ]; then
    say "Building $pkg"
    rm -rf "$BUILD/$pkg"
    tar -xJf "$ROOT/sources/$pkg.tar.xz" -C "$BUILD"
    (cd "$BUILD/$pkg" &&
      run $pkg.log env CC="$CC" ./configure --prefix="$HOST" &&
      run $pkg.log make -j"$JOBS" &&
      run $pkg.log make install)
    touch "$BUILD/$pkg/.built"
  fi
done

# Extract and patch the compiler. A changed patch set starts again from the archive.
SRC=$BUILD/gccsdk-$REVISION
STAMP=$(cd "$ROOT" && cat SHA256SUMS | $SUM | cut -d' ' -f1)
if [ ! -f "$SRC/.prepared" ] || [ "$(cat "$SRC/.prepared")" != "$STAMP" ]; then
  say "Preparing GCCSDK $REVISION"
  rm -rf "$SRC" "$BUILD/.built"
  tar -xzf "$ROOT/sources/gccsdk-3.4.6-apcs26.tar.gz" -C "$BUILD"
  while read -r name; do
    case $name in ''|'#'*) continue ;; esac
    say "Applying $name"
    (cd "$SRC" && run patches.log patch --batch -p1 --fuzz=0 -i "$ROOT/patches/$name")
  done <"$ROOT/patches/series"
  cp "$BUILD/autoconf-2.72/build-aux/config.guess" "$BUILD/autoconf-2.72/build-aux/config.sub" "$SRC/gcc/"
  (cd "$SRC/gcc" && run configure.log autoconf && run configure.log autoheader)
  echo "$STAMP" >"$SRC/.prepared"
fi

# configure records the prefix, so reconfigure when it changes.
if [ ! -f "$SRC/.configured" ] || [ "$(cat "$SRC/.configured")" != "$PREFIX" ]; then
  say "Configuring for $PREFIX"
  rm -f "$BUILD/.built"
  (cd "$SRC/gcc" && run configure.log env \
    CC="$CC" \
    CFLAGS='-O2 -fno-strict-aliasing -std=gnu89 -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types' \
    CXXFLAGS='-O2 -std=gnu++98' \
    ac_cv_prog_MAKEINFO=echo \
    ./configure --prefix="$PREFIX" --enable-checking=no)
  echo "$PREFIX" >"$SRC/.configured"
fi

if [ ! -f "$BUILD/.built" ]; then
  for target in setup libiberty-stg1 riscos-aof-stg1 gcc-stg1; do
    say "Building $target"
    (cd "$SRC/gcc" && run build.log make -j"$JOBS" $target)
  done
  touch "$BUILD/.built"
fi

[ -x "$PREFIX/bin/gcc" ] && [ -x "$PREFIX/bin/drlink" ] || die "build finished but gcc or drlink is missing from $PREFIX/bin"
say "Done: $PREFIX/bin/gcc and $PREFIX/bin/drlink"
say "Run ./tests/run.sh to check the compiler's output"
