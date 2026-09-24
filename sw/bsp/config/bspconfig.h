/* Hand-written equivalent of the Vitis 2025.2 standalone bspconfig.h for
 * Zynq-7000 Cortex-A9. CPU1 is compiled with -DUSE_AMP=1. The xiltimer
 * library is not used: XTime_* come from the standalone xtime_l.c. */
#ifndef BSPCONFIG_H
#define BSPCONFIG_H
#include "xmem_config.h"
#include "xparameters_ps.h"
#define PLATFORM_ZYNQ
#if defined(USE_AMP) && USE_AMP == 1
#define XPAR_CPU_ID 1
#else
#define XPAR_CPU_ID 0
#endif
#define XPAR_STDIN_IS_UARTPS
#define STDIN_BASEADDRESS  0xE0001000
#define STDOUT_BASEADDRESS 0xE0001000
#endif
