/* CPU0 (acquisition, DOA, UART): private DDR from 0x00100000. The build
 * checks that every load segment stays below 0x01000000. */
MEMORY { DDR : ORIGIN = 0x00100000, LENGTH = 0x00F00000 }
INCLUDE sections.ld
