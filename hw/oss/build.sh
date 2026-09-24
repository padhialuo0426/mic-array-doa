#!/usr/bin/env bash
# Open-source bitstream build (yosys + nextpnr-xilinx + prjxray) in the
# regymm/openxc7 container. Output: build/oss/top.bit
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd); out=$root/build/oss; mkdir -p "$out"
part=xc7z020clg400-2
image=${OPENXC7_IMAGE:-regymm/openxc7:latest}
docker run --rm -e SEED="${SEED:-1}" -v "$root":/work -w /work/build/oss "$image" bash -lc "
set -e
if [ ! -f chipdb-$part.bin ]; then
  (cd /nextpnr-xilinx/xilinx && python3 python/bbaexport.py --device $part --bba /work/build/oss/chipdb.bba)
  bbasm -l chipdb.bba chipdb-$part.bin && rm chipdb.bba
fi
yosys -l synth.log -p 'read_verilog -sv /work/hw/rtl/*.v /work/hw/oss/*.v; synth_xilinx -flatten -abc9 -arch xc7 -top top; write_json top.json' > /dev/null
# Block-RAM parity pins read back as 0 in this flow (seen on the board):
# refuse any RAMB whose DIP inputs carry data.
python3 -c 'import json,sys; m=json.load(open(\"top.json\"))[\"modules\"][\"top\"][\"cells\"]; bad=[n for n,c in m.items() if c[\"type\"].startswith(\"RAMB\") and any(isinstance(b,int) for p in (\"DIPADIP\",\"DIPBDIP\") for b in c[\"connections\"].get(p,[]))]; sys.exit(\"BRAM parity bits used: \"+\" \".join(bad)) if bad else None'
nextpnr-xilinx --chipdb chipdb-$part.bin --xdc /work/hw/oss/oss.xdc --json top.json --write top_routed.json --fasm top.fasm \
  --freq 100 --seed ${SEED:-1} > pnr.log 2>&1 || { tail -40 pnr.log; exit 1; }
grep 'Max frequency for clock' pnr.log | tail -2
# nextpnr-xilinx reports a timing failure but still writes the FASM.
if grep 'Max frequency for clock' pnr.log | tail -2 | grep -q FAIL; then echo 'timing failed: try another SEED' >&2; exit 1; fi
# nextpnr ties the unused MMCM CLKIN2 to GND through CLK_IN2_INT or _HCLK;
# prjxray-db encodes both with bit 28_1015 set, which every CLKFBIN route but
# the dedicated one requires clear, so fasm2frames rejects the design. The
# input is deselected (CLKINSEL=1): drop its route, leaving the mux at default.
# With COMPENSATION=INTERNAL nextpnr also ties CLKFBIN to VCC through
# CLK_IN3_INT and emits no feedback path, so the MMCM never locked on the
# board. Internal feedback is the CLKFBIN <- CLKFBOUT2IN pip (CLKFBOUT2IN is
# hard-wired to CLKFBOUT): replace the VCC route with it.
grep -Ev '_MMCM_CLKIN2\\.|\\.CMT_L_(LOWER_B|UPPER_T)_CLK_IN2_(INT|HCLK)\\.|HCLK_CMT_MUX_MMCM_CLKIN2\\.|\\.CMT_L_(LOWER_B|UPPER_T)_CLK_IN3_INT\\.' top.fasm |
  sed -E 's/^([^ ]+)\\.CMT_LR_(LOWER_B|UPPER_T)_MMCM_CLKFBIN\\.[^ ]+\$/\\1.CMT_LR_\\2_MMCM_CLKFBIN.CMT_LR_\\2_CLKFBOUT2IN/' > top_fixed.fasm
grep -q 'MMCM_CLKFBIN.CMT_LR_[A-Z_]*_CLKFBOUT2IN' top_fixed.fasm || { echo 'MMCM feedback fix-up did not apply' >&2; exit 1; }
fasm2frames --part $part --db-root /nextpnr-xilinx/xilinx/external/prjxray-db/zynq7 top_fixed.fasm > top.frames
xc7frames2bit --part_file /nextpnr-xilinx/xilinx/external/prjxray-db/zynq7/$part/part.yaml --part_name $part \
  --frm_file top.frames --output_file top.bit
chown -R $(id -u):$(id -g) /work/build/oss
"
ls -la "$out/top.bit"
