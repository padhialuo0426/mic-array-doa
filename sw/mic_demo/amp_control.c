#include "amp_control.h"
#include "xil_mmu.h"
#include "xil_io.h"
#include "xiltimer.h"
#include <string.h>
#include <stdio.h>
#include <math.h>
static volatile amp_shared *const shared=(volatile amp_shared*)AMP_ADDRESS;
void amp_init(void){
    Xil_SetTlbAttributes(AMP_ADDRESS,NORM_NONCACHE);
    memset((void*)shared,0,sizeof *shared);shared->version=1;
    __asm__ volatile("dmb sy" ::: "memory");shared->magic=AMP_MAGIC;
}
int amp_start_secondary(void){
    /* FSBL loads display.elf at this fixed linker address. CPU1 remains in
     * the BootROM OCM wait loop until CPU0 has initialized shared resources.
     * The build checks the ELF entry and both images' memory reservations. */
    Xil_SetTlbAttributes(0xffff0000U,NORM_NONCACHE);
    Xil_Out32(0xfffffff0U,0x02000000U);
    __asm__ volatile("dsb sy\nsev" ::: "memory");
    XTime start,now;XTime_GetTime(&start);
    do{
        if(shared->ready==AMP_READY){
            __asm__ volatile("dmb sy" ::: "memory");
            return shared->core_id==1U?0:-1;
        }
        if(shared->ready==0xdead0001U)return -1;
        XTime_GetTime(&now);
    }while(now-start<5U*(XTime)COUNTS_PER_SECOND);
    return -1;
}
void amp_mode(unsigned on){
    chirp_result r={0};r.status=CHIRP_BAD_INPUT;r.azimuth_deg=r.elevation_deg=r.level_dbfs=NAN;
    amp_publish(shared,&r,0);
    __asm__ volatile("dmb sy" ::: "memory");
    shared->command=((shared->command+0x100U)&0xffffff00U)|(on?1U:0U);
}
void amp_result(const chirp_result*r,uint64_t ms){amp_publish(shared,r,ms);}
void amp_audio(const uint32_t p[CHIRP_PACKET][8]){if(shared->ready==AMP_READY)amp_audio_push(shared,p);}
void amp_report(void){
    XTime now;XTime_GetTime(&now);uint32_t ms=(uint32_t)(now/(COUNTS_PER_SECOND/1000));
    printf("AMP ready=%08lx core=%lu heartbeat_age_ms=%lu video_frames=%lu hdmi_status=%08lx spectrum_drops=%lu spectrum_packets=%lu core1_busy_permille=%lu fft_max_us=%lu video_max_us=%lu\r\n",
        (unsigned long)shared->ready,(unsigned long)shared->core_id,(unsigned long)(ms-shared->heartbeat_ms),
        (unsigned long)shared->frame_count,(unsigned long)shared->hdmi_status,(unsigned long)shared->audio_drops,
        (unsigned long)shared->audio_consumed,(unsigned long)shared->busy_permille,(unsigned long)shared->fft_max_us,(unsigned long)shared->video_max_us);
}
