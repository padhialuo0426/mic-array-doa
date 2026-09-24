# 用开源工具链构建 BOOT.BIN

本文介绍如何在 Linux 或 macOS 上只用开源工具构建本项目的 `BOOT.BIN`，全程不需要安装 Vivado 或 Vitis。按本文操作，你会依次得到 PL 比特流、两个 A9 程序和 FSBL，再把它们打包成可以直接写入 TF 卡的 `BOOT.BIN`。环境准备好之后，一次完整构建在 Linux 上约 2 分钟，在 macOS 上约 4 分钟。

## 各步骤用到的工具

| 步骤 | Vivado/Vitis 流程 | 开源流程 |
|---|---|---|
| PL 综合、布局布线、比特流 | Vivado | [openXC7](https://github.com/openXC7) 容器镜像：yosys、nextpnr-xilinx、prjxray |
| PL 中的 Xilinx IP（AXI 互连、AXI DMA、FIFO、时钟、rgb2dvi） | Vivado IP 与 Digilent VHDL | `hw/oss/` 下的 Verilog 替代实现，寄存器与固件用到的部分兼容 |
| BSP、驱动、FSBL | Vitis 根据 `top.xsa` 生成 | `sw/bsp/` 中随仓库附带的 [embeddedsw](https://github.com/Xilinx/embeddedsw) 源码与手写配置 |
| A9 编译器 | Vitis 自带的 arm-none-eabi-gcc | 系统包管理器安装的 arm-none-eabi-gcc 与 newlib |
| 打包 `BOOT.BIN` | Vitis 自带的 bootgen | 从源码编译的开源 [bootgen](https://github.com/Xilinx/bootgen)（`xilinx_v2025.2`） |

两个流程共用 `hw/rtl/` 下的自有 RTL 和 `sw/` 下的全部应用源码，所以测向算法和显示界面完全相同。

## 开始前

Linux 和 macOS 上的构建命令完全相同，只是需要安装的软件不同。按你的系统准备好环境，再进行[构建](#构建)。

### Linux

你需要一台 x86-64 Linux 电脑，装有以下软件：

| 软件 | 用途 | Arch Linux | Debian/Ubuntu |
|---|---|---|---|
| Docker | 运行 openXC7 镜像 | `docker` | `docker.io` |
| arm-none-eabi-gcc 与 newlib | 编译 A9 程序和 FSBL | `arm-none-eabi-gcc arm-none-eabi-newlib` | `gcc-arm-none-eabi libnewlib-arm-none-eabi` |
| git、make、g++、OpenSSL 开发头文件 | 编译 bootgen（首次需联网从 GitHub 克隆源码） | `git make gcc openssl` | `git make g++ libssl-dev` |
| Python 3 | 打包前检查 ELF | `python` | `python3` |
| qemu-system-arm、mtools（可选） | 不接开发板检查启动过程 | `qemu-system-arm mtools` | `qemu-system-arm mtools` |

本节在 arm-none-eabi-gcc 16.2、Docker 29.8 上验证过。你的用户需要有权限运行 `docker`。

然后拉取 openXC7 镜像：

```bash
docker pull regymm/openxc7:latest
```

### macOS

你需要一台 Apple 芯片的 Mac，装有以下软件：

| 软件 | 用途 | 安装方式 |
|---|---|---|
| Xcode 命令行工具 | 编译 bootgen（clang、git、make），打包前检查 ELF（Python 3） | `xcode-select --install` |
| Apple container 与 Rosetta | 运行 openXC7 镜像 | 从 [container 发布页](https://github.com/apple/container/releases)安装后运行 `container system start`；Rosetta 用 `softwareupdate --install-rosetta --agree-to-license` 安装 |
| Homebrew 的 OpenSSL | 编译 bootgen | `brew install openssl@3` |
| [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)（含 newlib） | 编译 A9 程序和 FSBL | `brew install --cask gcc-arm-embedded` |

注意 Homebrew 另有一个同名的 formula `arm-none-eabi-gcc`，它只有编译器，不含 newlib，无法链接本项目的程序，请安装上表中的 cask。安装后，运行以下两条命令检查 `PATH` 中的 `arm-none-eabi-gcc` 是否可用：

```bash
arm-none-eabi-gcc -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -print-multi-directory
arm-none-eabi-gcc -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -print-file-name=libc.a
```

第一条应输出 `thumb/v7-a+fp/hard`，而不是 `.`；第二条应输出 `libc.a` 的完整路径，而不是只有 `libc.a` 这个文件名。

本节在 macOS 27.0、Apple container 1.4.1、Arm GNU Toolchain 15.3.Rel1 上验证过，系统自带的 GNU Make 3.81 和 Python 3.9 即可使用。

然后拉取 x86-64 版的 openXC7 镜像：

```bash
container image pull --platform linux/amd64 regymm/openxc7:latest
```

不要换用 `regymm/openxc7-arm` 镜像。它的 nextpnr-xilinx 版本较旧，遇到 `oss.xdc` 中的 `DRIVE` 属性会崩溃，也不支持 HDMI 输出所需的 OSERDESE2 主从级联。

构建脚本会自动识别 macOS：

- `hw/oss/build.sh` 改用 Apple 的 [container](https://github.com/apple/container) 运行 openXC7 镜像。这个镜像只有 x86-64 版本，脚本通过 Rosetta 运行它，并给容器分配 8 GB 内存（container 默认只给 1 GB，生成器件数据库和布局布线都不够用）。
- `scripts/build_bootgen.sh` 使用 Homebrew 安装的 OpenSSL，并补上 macOS 缺少的 `malloc.h`，bootgen 的源码不用改。

## 构建

以下命令都在仓库根目录运行，所有输出都放在 `build/` 下。

1. 编译开源 bootgen（只需一次；8 核 Linux 电脑或 Apple M5 上都约 10 秒）：

   ```bash
   scripts/build_bootgen.sh
   ```

   脚本会克隆 bootgen `xilinx_v2025.2` 并核对提交号，最后一行打印 bootgen 的路径：

   ```text
   <仓库路径>/build/vendor/bootgen/build/bin/bootgen
   ```

   编译过程中出现的 OpenSSL `deprecated` 警告不影响使用。

2. 构建 CPU0 测向程序、CPU1 显示程序和 FSBL：

   ```bash
   make -C sw -j8
   ```

   完成后，`build/sw/` 中有 `app.elf`、`display.elf` 和 `fsbl.elf`。链接器提示 `LOAD segment with RWX permissions` 是裸机程序的正常现象。

3. 构建 PL 比特流：

   ```bash
   hw/oss/build.sh
   ```

   第一次运行时，脚本会先从 prjxray 数据库生成约 130 MB 的器件数据库 `build/oss/chipdb-xc7z020clg400-2.bin`，首次构建在 Linux 上共约 2 分钟，之后每次约 75 秒；在 Apple M5 上首次约 4 分钟，之后每次约 100 秒。成功时输出两个时钟的时序结果和比特流文件：

   ```text
   Info: Max frequency for clock 'aclk': 111.31 MHz (PASS at 100.00 MHz)
   Info: Max frequency for clock 'pclk': 97.98 MHz (PASS at 74.25 MHz)
   -rw-r--r-- 1 user user 4045665 ... <仓库路径>/build/oss/top.bit
   ```

   频率数值随代码和布局种子变化，两行都显示 `PASS` 即可。同一份源码在 Linux 和 macOS 上得到的时序结果相同。

   其中的 `fasm` 包提示（关于 antlr 解析器）只影响速度，可以忽略。

4. 打包 `BOOT.BIN`：

   ```bash
   make -C sw boot BITSTREAM=../build/oss/top.bit \
     BOOTGEN=$PWD/build/vendor/bootgen/build/bin/bootgen
   ```

   打包前，`sw/check_elfs.py` 会检查各程序的入口地址、内存范围和 CPU1 的缓存设置。完成后生成 `build/sw/BOOT.BIN` 和 `build/sw/BOOT.BIN.sha256`。

5. （可选）不接开发板，用 QEMU 检查启动过程：

   ```bash
   sw/qemu/boot_check.sh build/sw
   ```

   脚本把 `BOOT.BIN` 放进一张模拟的 FAT32 SD 卡，从 SD 卡启动。FSBL 读卡、送出比特流并交给 CPU0。QEMU 没有 PL，所以程序停在 PL 检查处，这是预期结果：

   ```text
   PASS: SD boot reaches CPU0 (SD mode, autostart, L2 off); stops at the PL check as expected
   ```

   这一步尚未在 macOS 上验证。

## 只改软件时重新打包

修改 `sw/` 下的算法或显示代码、没有改动 `hw/` 时，不需要重新构建比特流，沿用已验证的 `build/oss/top.bit`：

```bash
make -C sw -j8
make -C sw boot BITSTREAM=../build/oss/top.bit \
  BOOTGEN=$PWD/build/vendor/bootgen/build/bin/bootgen
```

软件编译只需几秒，同一份源码每次得到的 ELF 逐字节相同。改动了 `hw/` 下的文件，就回到[构建](#构建)第 3 步重新构建比特流。

## 构建报错与处理

以下是 `hw/oss/build.sh` 和打包步骤可能报出的错误。

### `timing failed: try another SEED`

布局结果没有达到时序要求（aclk 100 MHz 或 pclk 74.25 MHz）。nextpnr 的布局受随机种子影响，换一个种子重新构建：

```bash
SEED=2 hw/oss/build.sh
```

种子 1 到 8 在本仓库当前代码上都能通过。修改了 `hw/` 下的 RTL 后，如果多个种子都失败，就需要检查新增逻辑的关键路径：`build/oss/pnr.log` 中 `Critical path report for clock 'aclk'` 一节列出了最慢的一条路径。

### `BRAM parity bits used`

综合结果中有块 RAM 用到了校验位（DIP/DOP）存数据。在这条工具链上，校验位读回恒为 0，数据会出错。常见原因是新增的存储器宽度为 9、18 或 36 位，yosys 把其中一部分位放进了校验位。

把存储器按 8 位一组拆成多个数组，参考 `hw/oss/axis_fifo.v` 的写法。

### `MMCM feedback fix-up did not apply`

`hw/oss/build.sh` 要把 MMCM 的反馈改为内部反馈通路，但在 FASM 中没有找到对应的连线。nextpnr 默认不生成 MMCM 反馈，不做这一步 MMCM 就无法锁定，HDMI 没有像素时钟。

这个错误通常出现在更换了 MMCM 的用法或位置之后。检查 `build/oss/top.fasm` 中 `MMCM_CLKFBIN` 所在的行，按实际的连线名称调整脚本中的替换规则。

### `FasmInconsistentBits`

fasm2frames 发现两个配置项要求同一位取不同的值。`hw/oss/build.sh` 已经处理了 MMCM 未用输入 CLKIN2 引起的这种冲突，原因见脚本中的注释。

改动时钟结构后如果出现新的冲突，报错信息会列出冲突的两行 FASM，据此找到对应的原语连线。

### `Set BITSTREAM=path/to/top.bit`

打包时没有指定比特流。`BITSTREAM` 的相对路径以 `sw/` 为起点，所以写成 `../build/oss/top.bit`。

## 开源流程的限制

- `hw/oss/s2mm_dma.v` 只实现固件用到的 AXI DMA 功能：simple 模式的 S2MM 通道、复位、状态位和 LENGTH。它不支持 SG 模式、MM2S 或中断输出。
- nextpnr 不分析跨时钟域路径和 IO 时序。跨时钟域的部分沿用 Vivado 设计中已有的同步器。
- `sw/bsp/ps7_init/` 是 Vivado 按 `hw/build.tcl` 中 PS 配置生成的初始化代码。修改 DDR、MIO 或时钟配置后，需要用 Vivado 重新生成这两个文件。
- 开源流程构建的比特流与 Vivado 构建的布局不同，时序余量也不同，两份 `BOOT.BIN` 不会逐字节相同。
- nextpnr 的时序报告对块 RAM 输入路径偏乐观：它报告画布显存的写入路径满足 100 MHz，但在板上会丢失写入。`hw/rtl/video_canvas.v` 因此在显存写入口前加了一级寄存器。修改 RTL 后，除了看时序报告，还要在板上做一次写入回读测试。

## 下一步

- 按 README 的[写入 TF 卡](../README.md#写入-tf-卡)一节，把 `build/sw/BOOT.BIN` 写入 TF 卡并上电。
- 按 README 的[通过 JTAG 临时加载](../README.md#通过-jtag-临时加载可选)一节，不写卡直接调试。打包步骤完成后，`build/sw/boot/` 中已有脚本需要的四个文件，可以直接作为 `BUILD_DIR`。
- 按[播放扫频测试音](../README.md#播放扫频测试音)一节，生成测试音，检查屏幕上的方向。
- 如果需要 Vivado 的时序报告做对照，按 [README 的构建一节](../README.md#构建)用 Vivado/Vitis 构建一份。
