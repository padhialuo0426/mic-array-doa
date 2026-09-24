#!/usr/bin/env bash
# QEMU check for the host-built BOOT.BIN (no board, no PL): on an emulated
# FAT32 SD card the FSBL (ps7_init, SD, FatFs, PCAP, handoff) must reach the
# CPU0 banner and stop at the expected PL check, since QEMU has no PL.
# Usage: sw/qemu/boot_check.sh BUILD_DIR   (BUILD_DIR holds BOOT.BIN and fsbl.elf)
# Needs qemu-system-arm (machine xilinx-zynq-a9) and mtools (mformat/mcopy).
set -euo pipefail
out=$(realpath "$1"); work="$out/qemu"; mkdir -p "$work"

run_until() { # log marker seconds qemu-args...
    local log=$1 marker=$2 limit=$3; shift 3
    rm -f "$log"
    qemu-system-arm -M xilinx-zynq-a9 -m 1G -display none -serial null -serial "file:$log" -monitor none "$@" &
    local pid=$!
    for _ in $(seq "$limit"); do sleep 1; grep -q "$marker" "$log" 2>/dev/null && break; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
    grep -q "$marker" "$log" || { echo "FAIL: '$marker' not reached in $log"; exit 1; }
}

img="$work/sd.img"
rm -f "$img"; truncate -s 64M "$img"
mformat -i "$img" -F -v MICBOOT ::
mcopy -i "$img" "$out/BOOT.BIN" ::/BOOT.BIN
run_until "$work/boot.log" 'ERROR incompatible PL' 60 -M boot-mode=sd -kernel "$out/fsbl.elf" -drive "file=$img,if=sd,format=raw"
grep -q 'BOOT mode=5 autostart=1' "$work/boot.log" && grep -q 'L2_CTRL=0' "$work/boot.log" \
    || { echo 'FAIL: unexpected boot banner'; cat "$work/boot.log"; exit 1; }
echo "PASS: SD boot reaches CPU0 (SD mode, autostart, L2 off); stops at the PL check as expected"
