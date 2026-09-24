/* SDT driver configuration tables, equivalent to the generated xdevcfg_g.c,
 * xsdps_g.c and xcortexa9_g.c of the Vitis 2025.2 FSBL for this hardware.
 * Values are the .drvcfg_sec contents of that FSBL: PCAP at 0xF8007000
 * (interrupt 0x4008, GIC 0xF8F01000), SD0 at 0xE0100000 with a 100 MHz input
 * clock, card detect and no write protect, CPU at 666666687 Hz. */
#include "xparameters.h"
#include "xdevcfg.h"
#include "xsdps.h"
#include "xcortexa9.h"

XDcfg_Config XDcfg_ConfigTable[] __attribute__((section(".drvcfg_sec"))) = {
	{"xlnx,zynq-devcfg-1.0", 0xF8007000U, 0x4008U, 0xF8F01000U},
	{NULL, 0U, 0U, 0U}
};

XSdPs_Config XSdPs_ConfigTable[] __attribute__((section(".drvcfg_sec"))) = {
	{"arasan,sdhci-8.9a", 0xE0100000U, 100000000U, 1U, 0U, 0U, 0U, 0U, 0U, 0U,
	 0x15U, 0U, 0U, 0U, 0U, 0U, 0U, 0U},
	{NULL}
};

XCortexa9_Config XCortexa9_ConfigTable __attribute__((section(".drvcfg_sec"))) = {
	666666687U
};
