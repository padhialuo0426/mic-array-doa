# Third-party notices

The root MIT license covers this project's original code. The following
components retain their own copyright notices and licenses.

| Component | Included location | License / notice |
|---|---|---|
| Digilent rgb2dvi | `hw/vendor/rgb2dvi/src/` | Six source files carry BSD-3-Clause notices; `ClockGen.vhd` is covered by the upstream repository MIT license. See [BSD notice](licenses/digilent-bsd-3-clause.txt) and [MIT notice](licenses/digilent-mit.txt). |
| ALINX AX7020 DDR settings | `hw/ax7020_ddr.tcl` | Original permission allows use and distribution while preserving its copyright and associated notice; see [ALINX notice](licenses/alinx.txt). |
| Noto Sans CJK 2.004 | Rasterized fixed labels in `sw/mic_demo/radar_assets.h` | Copyright 2014–2021 Adobe; [SIL Open Font License 1.1](licenses/noto-sans-cjk.txt). |
| DejaVu Sans Mono | ASCII bitmap glyphs in `sw/mic_demo/radar_assets.h` | Bitstream Vera font license and DejaVu notices, preserved in [font license](licenses/dejavu.txt). |
| Xilinx embeddedsw (standalone BSP, UART/PCAP/SD drivers, zynq_fsbl, xilffs) | `sw/bsp/embeddedsw/` | Unmodified files from [`Xilinx/embeddedsw`](https://github.com/Xilinx/embeddedsw) tag `xilinx_v2025.2`, commit `145cea8fcf98268c8b163f732c181f008e887e53`; MIT, see `sw/bsp/embeddedsw/license.txt`. FatFs (ChaN, one-clause BSD) and `zynq_fsbl/md5.c` (Eric Young, SSLeay license: this product includes cryptographic software written by Eric Young) keep their own notices. See [sw/bsp/README.md](sw/bsp/README.md). |
| Vivado PS initialization | `sw/bsp/ps7_init/` | Vivado 2025.2 output for this design's PS configuration, Copyright Xilinx, Inc.; MIT (SPDX header in the files). |
| Sipeed wiki images | `docs/images/micarray-photo.png`, `docs/images/micarray-layout.png` (downscaled, white background) | Copyright (c) 2021 Neucrack; [MIT License](licenses/sipeed-wiki-mit.txt). |

Digilent source is pinned to
[`f4613fff005b098065fd5d619a2b88e55720a423`](https://github.com/Digilent/vivado-library/tree/f4613fff005b098065fd5d619a2b88e55720a423/ip/rgb2dvi).
ALINX settings were extracted from `15_dma_loopback/ps_config.tcl` in
[`AX7020_2023.1`](https://github.com/alinxalinx/AX7020_2023.1), commit
`fcf1e4a239b0f47e8ee95dfde7c2eedc5685c327`.
Sipeed images come from `docs/hardware/assets/spmod/spmod_micarray/` in
[`sipeed/sipeed_wiki`](https://github.com/sipeed/sipeed_wiki/tree/e75d983e1199faf0dc0ebbc7340f72d0cfa3f8a0/docs/hardware/assets/spmod/spmod_micarray),
commit `e75d983e1199faf0dc0ebbc7340f72d0cfa3f8a0`.
The original vendor headers are preserved.

Font files are not bundled. Their rendered assets and bitmap glyphs are generated
by `tools/make_radar_assets.py`; applicable font notices accompany these assets.

External build dependencies are not distributed or relicensed by this
repository: Vivado/Vitis, AMD/Xilinx IP and device libraries, and the
open-source toolchain (bootgen, the openXC7 container). They keep their own
terms. The Vivado/Vitis build copies the project license and the bundled
third-party notices next to its output files.
