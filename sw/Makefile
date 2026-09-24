# Build both Cortex-A9 programs with a plain arm-none-eabi toolchain, without
# Vitis. Mirrors sw/build.py: same sources, flags, AMP translation-table patch
# and private DDR regions. Output: $(OUT)/app.elf (CPU0), $(OUT)/display.elf (CPU1)
# and $(OUT)/fsbl.elf (embeddedsw zynq_fsbl with this design's ps7_init).
#
#   make -C sw OUT=../build/sw
#   make -C sw OUT=../build/sw boot BITSTREAM=path/to/top.bit BOOTGEN=path/to/bootgen
CROSS ?= arm-none-eabi-
CC := $(CROSS)gcc
AR := $(CROSS)ar
OUT ?= ../build/sw
BSP := bsp/embeddedsw
ARCH := -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard
INCLUDES := -Ibsp/config -I$(BSP)/standalone/arm/cortexa9 -I$(BSP)/standalone/arm/common \
            -I$(BSP)/standalone/arm/common/gcc -I$(BSP)/standalone/common -I$(BSP)/uartps
# Flags as reported per domain in the Vitis 2025.2 build log: CPU0 BSP
# -O2 -g -fno-tree-loop-distribute-patterns -DNDEBUG, CPU1 BSP -O2 -g
# -DUSE_AMP=1 -DNDEBUG; applications -O0 -g3 overridden by -O2 (UserConfig).
BSP_FLAGS := $(ARCH) -DSDT -O2 -g -DNDEBUG $(INCLUDES)
BSP0_FLAGS := $(BSP_FLAGS) -fno-tree-loop-distribute-patterns
APP_FLAGS := $(ARCH) -g3 -U__clang__ -O2 -Wall -Wextra -Wstack-usage=4096 -Imic_demo $(INCLUDES)
LDLIBS := -Wl,--start-group -lxil -lgcc -lc -lm -Wl,--end-group
# Like Xilinx.spec: keep crti/crtbegin/crtend/crtn for .init/.fini and
# constructors, but use the BSP's _start (xil-crt0.S) instead of newlib crt0.
crt = $(shell $(CC) $(ARCH) -print-file-name=$(1))
CRT_BEGIN := $(call crt,crti.o) $(call crt,crtbegin.o)
CRT_END := $(call crt,crtend.o) $(call crt,crtn.o)

BSP_C := $(addprefix $(BSP)/standalone/arm/cortexa9/,xil_cache.c xil_mmu.c xtime_l.c) \
         $(addprefix $(BSP)/standalone/arm/common/,vectors.c xil_exception.c) \
         $(wildcard $(BSP)/standalone/arm/common/gcc/*.c) \
         $(addprefix $(BSP)/standalone/common/,xil_assert.c outbyte.c inbyte.c xil_printf.c xplatform_info.c) \
         $(BSP)/uartps/xuartps_hw.c
BSP_S := $(addprefix $(BSP)/standalone/arm/cortexa9/gcc/,asm_vectors.S boot.S cpu_init.S xil-crt0.S)

# FSBL: the embeddedsw 2025.2 zynq_fsbl application, its SD/PCAP drivers and
# FatFs, flags as in the Vitis log (BSP like CPU0; application -O0 -g3;
# link -Os --gc-sections -n with the upstream FSBL linker script).
FSBL_INCLUDES := $(INCLUDES) -I$(BSP)/devcfg -I$(BSP)/sdps -I$(BSP)/qspips -I$(BSP)/nandps \
                 -I$(BSP)/xilffs/include -I$(BSP)/zynq_fsbl -Ibsp/ps7_init
FSBL_BSP_FLAGS := $(ARCH) -DSDT -O2 -g -DNDEBUG -fno-tree-loop-distribute-patterns $(FSBL_INCLUDES)
FSBL_APP_FLAGS := $(ARCH) -DSDT -Wall -Wextra -O0 -g3 -U__clang__ $(FSBL_INCLUDES)
FSBL_BSP_C := $(BSP_C) $(addprefix $(BSP)/standalone/arm/cortexa9/,sleep.c usleep.c) \
              $(addprefix $(BSP)/standalone/common/,xil_sleepcommon.c xil_util.c xil_sutil.c) \
              $(addprefix $(BSP)/devcfg/,xdevcfg.c xdevcfg_hw.c xdevcfg_intr.c xdevcfg_sinit.c) \
              $(addprefix $(BSP)/sdps/,xsdps.c xsdps_card.c xsdps_host.c xsdps_options.c xsdps_sinit.c) \
              $(addprefix $(BSP)/xilffs/,diskio.c ff.c ffsystem.c ffunicode.c) bsp/config/drvcfg.c
FSBL_SRC := $(addprefix $(BSP)/zynq_fsbl/,fsbl_hooks.c image_mover.c main.c md5.c nand.c nor.c pcap.c qspi.c rsa.c sd.c) \
            bsp/ps7_init/ps7_init.c
FSBL_S := $(BSP)/zynq_fsbl/fsbl_handoff.S

CPU0_SRC := $(addprefix mic_demo/,main.c doa.c chirp.c led_ring.c realtime.c amp_ipc.c amp_control.c)
CPU1_SRC := $(addprefix mic_demo/,radar.c video.c led_ring.c amp_ipc.c) display_core/main.c

obj = $(patsubst %,$(OUT)/$(1)/%.o,$(2))

.PHONY: all clean boot check
BOOTGEN ?= bootgen
PYTHON ?= python3
all: $(OUT)/app.elf $(OUT)/display.elf $(OUT)/fsbl.elf

# CPU0: stock translation table (DDR inner+outer cacheable; CPU0 owns L2).
$(OUT)/cpu0/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(if $(filter $(BSP)/%,$<),$(BSP0_FLAGS),$(APP_FLAGS)) -MMD -c $< -o $@
$(OUT)/cpu0/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(BSP0_FLAGS) -MMD -c $< -o $@
$(OUT)/cpu0/translation_table.S.o: $(BSP)/standalone/arm/cortexa9/gcc/translation_table.S
	@mkdir -p $(dir $@)
	$(CC) $(BSP0_FLAGS) -c $< -o $@

# CPU1: USE_AMP=1 and every DDR section inner-cacheable, outer-noncacheable
# (0x15de6 -> 0x14de6), exactly as sw/build.py patches the Vitis BSP.
$(OUT)/cpu1/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(if $(filter $(BSP)/%,$<),$(BSP_FLAGS),$(APP_FLAGS)) -DUSE_AMP=1 -MMD -c $< -o $@
$(OUT)/cpu1/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(BSP_FLAGS) -DUSE_AMP=1 -MMD -c $< -o $@
$(OUT)/cpu1/translation_table_amp.S: $(BSP)/standalone/arm/cortexa9/gcc/translation_table.S
	@mkdir -p $(dir $@)
	grep -q '0x15de6' $< && sed 's/0x15de6/0x14de6/' $< > $@
$(OUT)/cpu1/translation_table.S.o: $(OUT)/cpu1/translation_table_amp.S
	$(CC) $(BSP_FLAGS) -DUSE_AMP=1 -c $< -o $@

$(OUT)/cpu0/libxil.a: $(call obj,cpu0,$(BSP_C) $(BSP_S)) $(OUT)/cpu0/translation_table.S.o
	$(AR) rcs $@ $^
$(OUT)/cpu1/libxil.a: $(call obj,cpu1,$(BSP_C) $(BSP_S)) $(OUT)/cpu1/translation_table.S.o
	$(AR) rcs $@ $^

# The vector table and boot code come from libxil.a; pull them in explicitly.
$(OUT)/app.elf: $(call obj,cpu0,$(CPU0_SRC)) $(OUT)/cpu0/libxil.a bsp/lscript_cpu0.ld bsp/sections.ld
	$(CC) $(ARCH) -nostartfiles -Wl,-T,bsp/lscript_cpu0.ld -Lbsp -L$(OUT)/cpu0 \
	  -Wl,--undefined=_vector_table -Wl,--undefined=MMUTable -o $@ $(CRT_BEGIN) $(call obj,cpu0,$(CPU0_SRC)) $(LDLIBS) $(CRT_END)
$(OUT)/display.elf: $(call obj,cpu1,$(CPU1_SRC)) $(OUT)/cpu1/libxil.a bsp/lscript_cpu1.ld bsp/sections.ld
	$(CC) $(ARCH) -nostartfiles -Wl,-T,bsp/lscript_cpu1.ld -Lbsp -L$(OUT)/cpu1 \
	  -Wl,--undefined=_vector_table -Wl,--undefined=MMUTable -o $@ $(CRT_BEGIN) $(call obj,cpu1,$(CPU1_SRC)) $(LDLIBS) $(CRT_END)

$(OUT)/fsbl/%.c.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(if $(filter $(FSBL_SRC),$<),$(FSBL_APP_FLAGS),$(FSBL_BSP_FLAGS)) -MMD -c $< -o $@
$(OUT)/fsbl/%.S.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(FSBL_BSP_FLAGS) -MMD -c $< -o $@
$(OUT)/fsbl/translation_table.S.o: $(BSP)/standalone/arm/cortexa9/gcc/translation_table.S
	@mkdir -p $(dir $@)
	$(CC) $(FSBL_BSP_FLAGS) -c $< -o $@
$(OUT)/fsbl/libxil.a: $(call obj,fsbl,$(FSBL_BSP_C) $(BSP_S)) $(OUT)/fsbl/translation_table.S.o
	$(AR) rcs $@ $^
$(OUT)/fsbl.elf: $(call obj,fsbl,$(FSBL_SRC) $(FSBL_S)) $(OUT)/fsbl/libxil.a $(BSP)/zynq_fsbl/lscript.ld
	$(CC) $(ARCH) -nostartfiles -Os -Wl,--gc-sections -n -Wl,-T,$(BSP)/zynq_fsbl/lscript.ld -L$(OUT)/fsbl \
	  -Wl,--undefined=_vector_table -Wl,--undefined=MMUTable -o $@ \
	  $(CRT_BEGIN) $(call obj,fsbl,$(FSBL_SRC) $(FSBL_S)) $(LDLIBS) $(CRT_END)

check: $(OUT)/app.elf $(OUT)/display.elf $(OUT)/fsbl.elf
	$(PYTHON) check_elfs.py $(OUT)

# BOOT.BIN from boot.bif (FSBL, bitstream, CPU0 then CPU1 image). Open-source
# bootgen 2025.2 reproduces the Vitis BOOT.BIN byte for byte from equal inputs.
boot: $(OUT)/BOOT.BIN
$(OUT)/BOOT.BIN: $(OUT)/app.elf $(OUT)/display.elf $(OUT)/fsbl.elf boot.bif $(BITSTREAM)
	@test -n "$(BITSTREAM)" || { echo 'Set BITSTREAM=path/to/top.bit'; exit 1; }
	$(PYTHON) check_elfs.py $(OUT)
	@mkdir -p $(OUT)/boot
	cp $(OUT)/fsbl.elf $(OUT)/app.elf $(OUT)/display.elf boot.bif $(OUT)/boot/
	cp $(BITSTREAM) $(OUT)/boot/top.bit
	cd $(OUT)/boot && $(BOOTGEN) -arch zynq -image boot.bif -o BOOT.BIN -w on
	mv $(OUT)/boot/BOOT.BIN $@
	cd $(OUT) && sha256sum BOOT.BIN > BOOT.BIN.sha256

clean:
	rm -rf $(OUT)

-include $(shell find $(OUT) -name '*.d' 2>/dev/null)
