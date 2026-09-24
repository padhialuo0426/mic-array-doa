#!/usr/bin/env bash
# Build Xilinx's open-source bootgen (Apache-2.0) at the 2025.2 tag into
# build/vendor/bootgen/build/bin/bootgen. Needs git, g++, make and OpenSSL
# headers. Its bundled lms-hash-sigs calls functions without prototypes,
# which current GCC rejects by default; relax only that diagnostic.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd); dir="$root/build/vendor/bootgen"
if [ ! -d "$dir/.git" ]; then
    git clone -q --depth 1 --branch xilinx_v2025.2 https://github.com/Xilinx/bootgen.git "$dir"
fi
test "$(git -C "$dir" rev-parse HEAD)" = 0e336a00dcff5842648f4a1e9f919abf7c960d97
args=(-j"$(getconf _NPROCESSORS_ONLN)" CFLAGS="-O -Wall -Wno-implicit-function-declaration")
if [ "$(uname)" = Darwin ]; then
    # bootgen's Makefile sets include paths and libraries only for Linux: take
    # that branch, find Homebrew's OpenSSL through the compiler's search paths
    # and stand in for <malloc.h>, which macOS does not have.
    shim="$root/build/vendor/macos-include"; mkdir -p "$shim"
    echo '#include <stdlib.h>' > "$shim/malloc.h"
    ssl=$(brew --prefix openssl@3)
    export CPATH="$ssl/include:$shim" LIBRARY_PATH="$ssl/lib"
    args+=(UNAME=Linux)
fi
make -C "$dir" "${args[@]}" >/dev/null
echo "$dir/build/bin/bootgen"
