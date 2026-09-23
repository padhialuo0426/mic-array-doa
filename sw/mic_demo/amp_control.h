#ifndef MIC_AMP_CONTROL_H
#define MIC_AMP_CONTROL_H
#include "amp_ipc.h"
void amp_init(void);
int amp_start_secondary(void);
void amp_mode(unsigned radar_on);
void amp_result(const chirp_result*r,uint64_t now_ms);
void amp_audio(const uint32_t packet[CHIRP_PACKET][8]);
void amp_report(void);
#endif
