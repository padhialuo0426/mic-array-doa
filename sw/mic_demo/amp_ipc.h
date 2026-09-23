#ifndef MIC_AMP_IPC_H
#define MIC_AMP_IPC_H
#include "chirp.h"
#define AMP_ADDRESS 0x12000000U
#define AMP_MAGIC 0x414d5031U
#define AMP_READY 0xa9010001U
#define AMP_SLOTS 8U
/* One uncached 1 MiB section, disjoint from application and DMA regions.
 * CPU0 owns fields through audio[]; CPU1 owns all fields after audio[]. */
typedef struct {
    uint32_t magic,version,command,result_seq;
    uint64_t result_ms;
    chirp_result result;
    uint32_t audio_head,audio_drops;
    int32_t audio[AMP_SLOTS][CHIRP_PACKET];
    uint32_t audio_tail,ready,core_id,heartbeat_ms,frame_count,hdmi_status;
    uint32_t fft_max_us,video_max_us,busy_permille,audio_consumed;
} amp_shared;
_Static_assert(sizeof(amp_shared)<16384,"IPC exceeds reserved mailbox");
void amp_publish(volatile amp_shared*m,const chirp_result*r,uint64_t ms);
int amp_snapshot(volatile amp_shared*m,chirp_result*r,uint64_t*ms,uint32_t*sequence);
int amp_audio_push(volatile amp_shared*m,const uint32_t frames[CHIRP_PACKET][8]);
int amp_audio_pop(volatile amp_shared*m,int32_t mono[CHIRP_PACKET]);
#endif
