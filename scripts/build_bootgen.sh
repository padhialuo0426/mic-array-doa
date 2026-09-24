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
make -C "$dir" -j"$(nproc)" CFLAGS="-O -Wall -Wno-implicit-function-declaration" >/dev/null
echo "$dir/build/bin/bootgen"
