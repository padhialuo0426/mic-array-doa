# Third-party notices

The root MIT license covers this project's original code. The following
components retain their own copyright notices and licenses.

| Component | Included location | License / notice |
|---|---|---|
| Digilent rgb2dvi | `hw/vendor/rgb2dvi/src/` | Six source files carry BSD-3-Clause notices; `ClockGen.vhd` is covered by the upstream repository MIT license. See [BSD notice](licenses/digilent-bsd-3-clause.txt) and [MIT notice](licenses/digilent-mit.txt). |
| ALINX AX7020 DDR settings | `hw/ax7020_ddr.tcl` | Original permission allows use and distribution while preserving its copyright and associated notice; see [ALINX notice](licenses/alinx.txt). |
| Noto Sans CJK 2.004 | Rasterized fixed labels in `sw/mic_demo/radar_assets.h` | Copyright 2014–2021 Adobe; [SIL Open Font License 1.1](licenses/noto-sans-cjk.txt). |
| DejaVu Sans Mono | ASCII bitmap glyphs in `sw/mic_demo/radar_assets.h` | Bitstream Vera font license and DejaVu notices, preserved in [font license](licenses/dejavu.txt). |
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

Vivado/Vitis, AMD/Xilinx IP, device libraries and generated BSP sources are
external build dependencies, not relicensed or distributed by this repository.
The build copies the project license and bundled third-party notices alongside
the output files; separately supplied dependencies retain their own terms.
