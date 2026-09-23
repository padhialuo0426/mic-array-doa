#ifndef MIC_VIDEO_H
#define MIC_VIDEO_H
#include "chirp.h"
int video_init(void);
void video_bars(int on);
void video_result(const chirp_result*r,uint64_t now_ms);
void video_feed(const int32_t mono[CHIRP_PACKET]);
/* One bounded upload slice or one CPU render, never waits for vertical blank. */
int video_service(uint64_t now_ms);
void video_clear(void);
uint32_t video_status(void);
#endif
