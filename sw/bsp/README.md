# Standalone BSP for building without Vitis

`sw/Makefile` builds the CPU0 program, the CPU1 display program and the FSBL with a plain `arm-none-eabi` toolchain. This directory holds everything those builds take from Xilinx/AMD, plus the few files Vitis would normally generate. For the build steps, see [Build BOOT.BIN with the open-source toolchain](../../docs/open-toolchain.md) (Chinese).

## Vendored sources (unmodified)

`embeddedsw/` contains files copied byte for byte from [Xilinx/embeddedsw](https://github.com/Xilinx/embeddedsw) tag `xilinx_v2025.2`, commit `145cea8fcf98268c8b163f732c181f008e887e53`. This is the release Vitis 2025.2 uses. The directory layout maps as follows:

| Here | Upstream |
|---|---|
| `embeddedsw/standalone/` | `lib/bsp/standalone/src/` |
| `embeddedsw/zynq_fsbl/` | `lib/sw_apps/zynq_fsbl/src/` |
| `embeddedsw/xilffs/` | `lib/sw_services/xilffs/src/` |
| `embeddedsw/{devcfg,sdps,qspips,nandps,uartps}/` | `XilinxProcessorIPLib/drivers/<name>/src/` |

`ps7_init/ps7_init.{c,h}` is the Vivado 2025.2 output for the PS configuration in `hw/build.tcl`, copied unchanged. It holds the DDR, PLL and MIO initialization. Regenerate it with Vivado only if the PS configuration changes.

The only change to upstream behaviour is applied at build time, not in these files. The CPU1 translation table maps every DDR section with `0x14de6` instead of `0x15de6`, meaning inner-cacheable and outer-noncacheable, so CPU0 alone owns the shared L2. `sw/build.py` applies the same patch to the Vitis BSP.

## Files written for this project

These files replace what Vitis generates from `top.xsa`:

- **`config/xparameters.h`, `config/bspconfig.h`, `config/xmem_config.h`**: CPU clock 666,666,687 Hz, DDR 0x00100000–0x3FFFFFFF, UART1, SD0 and PCAP base addresses, and the driver instance counts. The drivers are built in their system-device-tree (SDT) mode, as Vitis 2025.2 builds them.
- **`config/drvcfg.c`**: the SDT driver tables, with the same values as the `.drvcfg_sec` section of the Vitis-built FSBL.
- **`config/xilffs_config.h`**: the FatFs options that match the Vitis FSBL.
- **`config/xiltimer.h`**: a shim for the timer header the application includes. It provides the standalone `xtime_l.h` global-timer API.
- **`lscript_cpu0.ld`, `lscript_cpu1.ld`, `sections.ld`**: the section layout, heap size and stack sizes of the Vitis-built ELFs. The FSBL uses the upstream `embeddedsw/zynq_fsbl/lscript.ld` unchanged.

## Licenses

Most vendored files carry `SPDX-License-Identifier: MIT`. See `embeddedsw/license.txt`. Two components carry their own licenses:

- **FatFs** (`embeddedsw/xilffs/ff*.c`, `include/ff.h`, `include/ffconf.h`, `include/diskio.h`): ChaN's one-clause BSD license, which requires keeping the copyright notice.
- **`embeddedsw/zynq_fsbl/md5.c`**: Eric Young's SSLeay license, which requires keeping the copyright notice and attributing the author in the documentation.
