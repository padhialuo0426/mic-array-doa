/* xilffs defaults of Vitis 2025.2 (xilffs.cmake), matching the functions
 * present in the Vitis-built FSBL: SD interface, read/write, f_mkfs, no LFN,
 * no string functions, single partition, 35 volumes, word access. */
#ifndef XILFFS_CONFIG_H
#define XILFFS_CONFIG_H
#include "xparameters.h"
#define FILE_SYSTEM_INTERFACE_SD
#define FILE_SYSTEM_USE_MKFS
#define FILE_SYSTEM_NUM_LOGIC_VOL 35
#define FILE_SYSTEM_WORD_ACCESS
#define FILE_SYSTEM_MAX_SECTOR_SIZE 4096
#endif
