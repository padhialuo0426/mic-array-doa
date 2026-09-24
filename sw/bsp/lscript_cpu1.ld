/* CPU1 (display, USE_AMP=1): private 16 MiB at 0x02000000; CPU0 wakes it at
 * this entry address. */
MEMORY { DDR : ORIGIN = 0x02000000, LENGTH = 0x01000000 }
INCLUDE sections.ld
