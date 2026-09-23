#include "video.h"
#include "radar.h"
#include "xil_io.h"
#define BASE 0x43c40000U
#define CANVAS (BASE+0x20000U)
#define CHUNK 64U
static int available,bars=1,mode_dirty=1;
static unsigned cursor=RADAR_WORDS;
static uint64_t last_render,next_status;
static const uint32_t *image;
uint32_t video_status(void){return available?Xil_In32(BASE+4):0;}
int video_init(void){available=Xil_In32(BASE+8)==0x48444d31U;radar_init();return available?0:-1;}
void video_bars(int on){bars=!!on;mode_dirty=1;cursor=RADAR_WORDS;last_render=0;}
void video_clear(void){radar_init();last_render=0;}
void video_result(const chirp_result*r,uint64_t now){radar_result(r,now);}
void video_feed(const int32_t mono[CHIRP_PACKET]){if(available&&!bars)radar_spectrum(mono);}
int video_service(uint64_t now){
    if(!available||now<next_status)return 0;
    if(bars&&!mode_dirty)return 0;
    if(!bars&&cursor>=RADAR_WORDS&&!mode_dirty&&now-last_render<100)return 0;
    if(video_status()&1){next_status=now+1;return 0;}
    if(bars){if(mode_dirty){Xil_Out32(BASE,3);mode_dirty=0;return 1;}return 0;}
    if(cursor<RADAR_WORDS){
        unsigned end=cursor+CHUNK;if(end>RADAR_WORDS)end=RADAR_WORDS;
        for(;cursor<end;cursor++)Xil_Out32(CANVAS+4*cursor,image[cursor]);
        if(cursor==RADAR_WORDS){__asm__ volatile("dsb sy" ::: "memory");Xil_Out32(BASE,1);mode_dirty=0;}
        return 1;
    }else if(mode_dirty||now-last_render>=100){image=radar_render(now);last_render=now;cursor=0;return 1;}
    return 0;
}
