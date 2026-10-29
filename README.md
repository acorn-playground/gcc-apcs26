# gcc-apcs26

GCCSDK 3.4.6, the 26-bit ARM2/APCS-26 RISC OS C compiler and the Drlink
linker, patched to build and generate correct code on modern 64-bit hosts.

This is the last GCCSDK release that targets the original Acorn Archimedes:
ARM2 and ARM3 processors, 26-bit addressing, the APCS-26 calling convention,
AOF object files and the SharedCLibrary. Built unmodified on a 64-bit machine
it either crashes or, worse, quietly generates wrong code. The patches here
fix the host bugs behind that without changing what the compiler generates for
the target.

It is maintained as part of [ArcLibre](https://github.com/acorn-playground/ArcLibre), a freely redistributable RISC OS 3.11-compatible ROM, which compiles its original C components (SharedCLibrary, RISC_OSLib, FilerAct, Draw, Paint
and others) with it.

## Quick start

```sh
git clone https://github.com/acorn-playground/gcc-apcs26.git
cd gcc-apcs26
./build.sh
./tests/run.sh
```

That produces `install/bin/gcc` and `install/bin/drlink`. A first build takes
a few minutes. Everything needed is in this repository; nothing is downloaded.

Options are environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `PREFIX` | `./install` | Where the compiler is installed |
| `JOBS` | `4` | Parallel make jobs |
| `CC` | `clang`, else `cc` | Host C compiler |
| `BUILD_DIR` | `./build` | Scratch directory (logs in `build/logs`) |

Running `./build.sh` again only redoes the steps whose inputs changed. Delete
`build/` and `install/` to start from scratch.

### Requirements

- A host C compiler, `make`, `patch` and `tar` with xz support.
- macOS: the Xcode command line tools (`xcode-select --install`) are enough;
  they include the Bison, flex and M4 the build uses.
- Linux: Clang, Bison, flex and GNU M4 as well. On Debian or Ubuntu:

  ```sh
  sudo apt install build-essential clang bison flex m4 xz-utils
  ```

  `build.sh` uses Clang when it's installed. Use it on Linux: GCC 15
  defaults to C23, which breaks the bundled M4's gnulib on glibc 2.43.

GNU M4 and Autoconf are built from the copies in `sources/`, so their host
versions don't matter.

### Tested hosts

- **Apple Silicon macOS** (Apple Clang 21): `build.sh` and `tests/run.sh`.
- **x86-64 Linux** (Ubuntu 26.04, Clang 21, glibc 2.43): built as part of
  ArcLibre, whose ROM it compiles to the same bytes as the macOS build.
  `tests/run.sh` has not been run there yet.

Intel macOS has not been tried. Reports and fixes are welcome.

## Using it

```sh
install/bin/gcc -mcpu=arm2 -mapcs-26 -mlibscl -O2 -c hello.c -o hello.o
```

- `-mcpu=arm2 -mapcs-26` selects the original 26-bit target. GCC prints a
  note that future releases won't support `-mapcs-26`; that's expected.
- `-mlibscl` uses the SharedCLibrary calling conventions.
- `-mmodule` builds code for a relocatable module.
- `-S` gives assembly that other AOF assemblers, such as AsAsm, accept.
- `gcc -c` assembles with the bundled GCCSDK assembler and gives an AOF object.

**There is no C library here.** This repository builds the compiler and
linker only. To link a program you need the SharedCLibrary headers and its
stubs (the small library that binds a program to the SharedCLibrary in ROM),
for example built from RISC OS Open's Apache-licensed SharedCLibrary sources,
as ArcLibre does. GCCSDK's own UnixLib and other target libraries are not
built.

## The patches

Applied in order by `build.sh` from `patches/series`, each with
`patch -p1 --fuzz=0`:

| Patch | What it fixes |
|---|---|
| `gccsdk-3.4.6-host.patch` | Recognises ARM64 hosts and regenerates configure with modern `config.guess`/`config.sub`. Old instruction-generator callbacks were cast to variadic function pointers; ARM64 passes variadic arguments differently, so the compiler crashed. Fixes an out-of-bounds read in `gengtype`, a pointer truncated by an implicit `int` declaration (`aof_rodata_section`), and lets the legacy assembler build despite warnings. |
| `gccsdk-3.4.6-rom-library.patch` | Only active with `-mlibrary-static-data-offset`, for code that runs from ROM inside the SharedCLibrary's data contract: read-only constants stay in ROM rather than being relocated into RAM. ArcLibre needs it; ordinary programs are unaffected. |
| `gccsdk-3.4.6-signed-frame-offset.patch` | `arm_compute_initial_elimination_offset` returned an unsigned 32-bit value. A frameless function's -4 became +4294967292 on a 64-bit host, producing `sub a2, sp, #-4294967296`: an invalid stack address for the first stacked argument. |
| `gccsdk-3.4.6-signed-prologue-offset.patch` | The prologue negated an unsigned `args_to_push`, so every function with a frame got `sub fp, ip, #-4294967292` instead of `sub fp, ip, #4`. Assemblers that wrap immediates to 32 bits happen to encode this correctly; the patch makes the output correct regardless. |
| `gccsdk-3.4.6-case-insensitive.patch` | RISC OS filenames are case-insensitive, and sources rely on it (`#include "h.EditIntern.txt1"` for a file stored as `h.editintern.txt1`). On a case-sensitive host such as Linux, when an `#include` isn't found exactly, each missing path component takes its unique case-insensitive match. The spelling the source used is kept for `__FILE__` and line markers. On macOS's case-insensitive volumes the exact open already succeeds, so nothing changes there. |

## Tests

`./tests/run.sh` needs no RISC OS machine or emulator. It compiles each file in
`tests/cases` with four profiles (application `-O2` and `-Os`, module, and ROM
library) and checks that:

- the assembly matches `tests/expected` exactly (generated on Apple Silicon
  macOS; a host-dependent bug shows up as a difference);
- no output contains a 32-bit constant wrapped through a 64-bit integer;
- `gcc -c` produces an AOF object and `drlink` is installed.

The cases cover seven-argument functions (stack arguments, with and without a
frame), variadic functions with and without a frame, switch tables, structure
copies, division, floating point, recursion and read-only data.
`./tests/run.sh --update` rewrites the expected files after an intended change.

ArcLibre runs the generated code on emulated ARM2 hardware. Those tests need
the ROM and an emulator, so they live in ArcLibre rather than here.

## Sources

| File | What it is |
|---|---|
| `sources/gccsdk-3.4.6-apcs26.tar.gz` | GCCSDK at revision `f79cb59110e2d13566678d923dadba0f97a1321d` of [riscos-dot-info/gccsdk](https://github.com/riscos-dot-info/gccsdk) (`release_3_4_6`), with one directory removed (below) |
| `sources/m4-1.4.20.tar.xz` | GNU M4, the official release archive |
| `sources/autoconf-2.72.tar.xz` | GNU Autoconf, the official release archive |

`SHA256SUMS` covers every archive and patch, and `build.sh` checks it before
building.

The GCCSDK archive is the upstream download for that revision (SHA-256
`28efa344...`) with the `gcc/riscos-aof/cmunge` directory removed. CMunge is not
needed to build the compiler, and its own licence restricts commercial
bundling, so it is not covered by the compiler's GPL. Every remaining file is
byte-for-byte unchanged; `sources/selection.json` lists both archive hashes and
every excluded file with its hash.

## Licence

GCC, Drlink and the rest of the GCCSDK sources are under the GNU General Public
License, version 2 or later, as stated in their own files; `COPYING` is the
GPL version 2 text. The patches, build script and tests here are under the same
licence. M4 and Autoconf keep their own GNU licences inside their archives.

The compiler is a host tool. Code it compiles is not covered by the GPL
because of that; any library you link against has its own terms.

## Credits

GCC is by the Free Software Foundation and its contributors. Drlink is by David
Daniels. The RISC OS port and AOF tools are by the GCCSDK developers, among them
Nick Burrett, Peter Naulls and John Tytgat. The 64-bit host patches were made
for ArcLibre.
