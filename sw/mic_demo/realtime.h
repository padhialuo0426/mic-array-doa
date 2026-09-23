#ifndef MIC_REALTIME_H
#define MIC_REALTIME_H
#include <stdint.h>
void chirp_stream(const uint8_t mapping[7]);
void chirp_replay(uint32_t frames,const uint8_t mapping[7]);
#endif
