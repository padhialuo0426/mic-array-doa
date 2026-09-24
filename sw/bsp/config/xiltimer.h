/* Compatibility shim: the application includes "xiltimer.h" (Vitis 2025.2
 * default timer library) only for XTime, XTime_GetTime and COUNTS_PER_SECOND,
 * which the standalone Cortex-A9 xtime_l.h provides with the same global timer. */
#ifndef XILTIMER_SHIM_H
#define XILTIMER_SHIM_H
#include "xtime_l.h"
#endif
