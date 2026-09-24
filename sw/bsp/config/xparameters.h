/* Hand-written equivalent of the Vitis 2025.2 SDT xparameters.h for the
 * AX7020 hardware in hw/build.tcl. Values come from top.xsa
 * (PCW_ACT_APU_PERIPHERAL_FREQMHZ=666.666687, DDR 0x00100000..0x3FFFFFFF,
 * UART1 at 0xE0001000); the Vitis build's COUNTS_PER_SECOND is 333333343.
 * The CPU clock is defined before xparameters_ps.h, which derives
 * XPAR_CPU_CORTEXA9_CORE_CLOCK_FREQ_HZ from it. */
#ifndef XPARAMETERS_H
#define XPARAMETERS_H
#define XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ 666666687U
#include "xparameters_ps.h"
#define XPAR_PS7_DDR_0_S_AXI_BASEADDR 0x00100000U
#define XPAR_PS7_DDR_0_S_AXI_HIGHADDR 0x3FFFFFFFU
#define XPAR_PS7_DDR_0_BASEADDRESS    0x00100000U
#define XPAR_PS7_DDR_0_HIGHADDRESS    0x3FFFFFFFU
/* PS peripherals enabled in hw/build.tcl, SDT instance numbering (UART1 is
 * the only UART, hence instance 0). Values match the .drvcfg_sec tables of
 * the Vitis-built FSBL. */
#define XPAR_XUARTPS_0_BASEADDR       0xE0001000U
#define XPAR_XSDPS_NUM_INSTANCES      2U  /* SDT: instances + NULL terminator entry */
#define XPAR_XSDPS_0_BASEADDR         0xE0100000U
#define XPAR_XDCFG_NUM_INSTANCES      2U  /* as in the Vitis FSBL: Stat[2], SdInstance[2] */
#define XPAR_XDEVCFG_0_BASEADDR       0xF8007000U
#endif
