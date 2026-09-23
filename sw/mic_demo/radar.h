#ifndef MIC_RADAR_H
#define MIC_RADAR_H
#include "chirp.h"
#define RADAR_WIDTH 640
#define RADAR_HEIGHT 360
#define RADAR_WORDS (RADAR_WIDTH*RADAR_HEIGHT/8)
/* Portable display processing, independent of the direction estimator. */
void radar_init(void);
void radar_result(const chirp_result *r,uint64_t now_ms);
void radar_spectrum(const int32_t mono[CHIRP_PACKET]);
const uint32_t *radar_render(uint64_t now_ms);
void radar_project(float az,float el,int *x,int *y);
#endif
