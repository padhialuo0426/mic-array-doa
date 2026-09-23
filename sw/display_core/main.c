/* CPU1: display only. BSP compiled with USE_AMP=1 and inner-only DDR cache.
 * CPU0 owns UART, DMA, global timer and shared L2 initialization/control. */
#include "amp_ipc.h"
#include "video.h"
#include "xil_io.h"
#include "xil_mmu.h"
#include "xiltimer.h"
#ifndef USE_AMP
#error CPU1 must use the AMP BSP
#endif
static volatile amp_shared *const shared=(volatile amp_shared*)AMP_ADDRESS;
static int32_t mono[CHIRP_PACKET];
static uint64_t tick(void){
    uint32_t hi,lo,again;
    do{hi=Xil_In32(0xf8f00204U);lo=Xil_In32(0xf8f00200U);again=Xil_In32(0xf8f00204U);}while(hi!=again);
    return ((uint64_t)hi<<32)|lo;
}
static uint64_t millis(uint64_t ticks){return ticks/(COUNTS_PER_SECOND/1000);}
int main(void){
    uint32_t mpidr;__asm__ volatile("mrc p15,0,%0,c0,c0,5":"=r"(mpidr));
    Xil_SetTlbAttributes(AMP_ADDRESS,NORM_NONCACHE);
    while(shared->magic!=AMP_MAGIC||shared->version!=1)__asm__ volatile("nop");
    shared->core_id=mpidr&3U;
    if((mpidr&3U)!=1||video_init()){shared->ready=0xdead0001U;for(;;);}
    __asm__ volatile("dmb sy" ::: "memory");
    shared->ready=AMP_READY;
    uint32_t command=UINT32_MAX,sequence=0;uint64_t last=tick(),busy=0;
    for(;;){
        uint64_t now=tick();uint32_t next=shared->command;
        if(next!=command){command=next;video_clear();video_bars((next&1)==0);shared->audio_tail=shared->audio_head;}
        chirp_result r;uint64_t stamp;
        if(amp_snapshot(shared,&r,&stamp,&sequence))video_result(&r,stamp);
        uint64_t start=tick();
        if(amp_audio_pop(shared,mono)){
            video_feed(mono);shared->audio_consumed++;
            uint64_t elapsed=tick()-start;busy+=elapsed;
            uint32_t us=(uint32_t)(elapsed/(COUNTS_PER_SECOND/1000000));if(us>shared->fft_max_us)shared->fft_max_us=us;
        }
        start=tick();
        if(video_service(millis(now))){
            uint64_t elapsed=tick()-start;busy+=elapsed;
            uint32_t us=(uint32_t)(elapsed/(COUNTS_PER_SECOND/1000000));if(us>shared->video_max_us)shared->video_max_us=us;
        }
        if(now-last>COUNTS_PER_SECOND/2){
            shared->busy_permille=(uint32_t)(1000*busy/(now-last));busy=0;last=now;
            shared->heartbeat_ms=(uint32_t)millis(now);
            shared->frame_count=Xil_In32(0x43c4000cU);shared->hdmi_status=video_status();
        }
    }
}
