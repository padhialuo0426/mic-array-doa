/* Hardware adapter. All numerical processing and display mapping are portable.
 * DMA owns one noncached packet, CPU owns the other; the search yields between
 * small batches. UART TX never blocks acquisition. */
#include "realtime.h"
#include "chirp.h"
#include "led_ring.h"
#include "amp_control.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_mmu.h"
#include "xiltimer.h"
#include "xuartps_hw.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
#define CAP 0x43c00000U
#define DMA 0x40400000U
#define LED 0x43c10000U
#define UART 0xe0001000U
#define BUFFER_ADDR 0x10000000U
#define PACKET_BYTES (CHIRP_PACKET*32U)
#define CTRL 0x30U
#define STATUS 0x34U
#define DEST 0x48U
#define LENGTH 0x58U
#define SEARCH_BATCH 16U
#define LED_FIRST_INDEX 0
#define LED_CHAIN_REVERSED 0
static uint64_t storage[CHIRP_STORAGE_BYTES/sizeof(uint64_t)];
static uint32_t packet[CHIRP_PACKET][8];
static char tx[2048];
static unsigned tx_head,tx_tail,tx_dropped;
static uint32_t rd(uint32_t b,uint32_t o){return Xil_In32(b+o);}
static void wr(uint32_t b,uint32_t o,uint32_t v){Xil_Out32(b+o,v);}
static XTime tick(void){XTime t;XTime_GetTime(&t);return t;}
static void arm(unsigned active){wr(DMA,STATUS,0x1000);wr(DMA,DEST,BUFFER_ADDR+active*PACKET_BYTES);wr(DMA,LENGTH,PACKET_BYTES);}
static void enqueue(const char *line) {
    unsigned n=(unsigned)strlen(line),free_bytes=(tx_tail-tx_head-1)&2047;
    if(n>free_bytes){tx_dropped++;return;}
    for(unsigned i=0;i<n;i++){tx[tx_head]=line[i];tx_head=(tx_head+1)&2047;}
}
static void uart_service(void) {
    for(unsigned n=0;n<32&&tx_tail!=tx_head&&!XUartPs_IsTransmitFull(UART);n++) {
        XUartPs_WriteReg(UART,XUARTPS_FIFO_OFFSET,(uint32_t)(unsigned char)tx[tx_tail]);tx_tail=(tx_tail+1)&2047;
    }
}
static void show_result(const chirp_result*r) {
    char line[256],az[24],el[24];
    if(r->azimuth_valid)snprintf(az,sizeof(az),"%.0f",r->azimuth_deg);else strcpy(az,"NA");
    if(isfinite(r->elevation_deg))snprintf(el,sizeof(el),"%.0f",r->elevation_deg);else strcpy(el,"NA");
    snprintf(line,sizeof(line),"CHIRP seq=%lu status=%s az=%s el=%s level_dbfs=%.2f snr=%.1f quality=%.4f gate_delta=%.2f latency_ms=%.1f\r\n",
        (unsigned long)r->frame_sequence,chirp_status_name(r->status),az,el,r->level_dbfs,r->snr_db,r->quality,r->gate_difference_deg,
        1000.0*r->latency_frames/CHIRP_FS);
    enqueue(line);
}
static void led_refresh(const uint32_t pixels[12]) {
    if(rd(LED,4)&1U)return;
    for(unsigned i=0;i<12;i++)wr(LED,0x10+4*i,pixels[i]);
    wr(LED,0,1);
}
static void led_blank(void) {
    XTime start=tick();
    while(rd(LED,4)&1U)if(tick()-start>COUNTS_PER_SECOND/100)return;
    wr(LED,0,2);
}
static void cached_algorithm(void) {
    for(uint32_t address=BUFFER_ADDR;address<BUFFER_ADDR+32U*1024U*1024U;address+=0x100000U)
        Xil_SetTlbAttributes(address,NORM_NONCACHE);
    Xil_DCacheEnable();
}
/* Target/host parity diagnostic: process the saved finite capture on the A9
 * without new acquisition or LED indication. Same core, mapping and cache
 * attributes as streaming; a completed search is serviced before advancing. */
void chirp_replay(uint32_t frames,const uint8_t mapping[7]) {
    if(frames<CHIRP_PACKET||frames>32U*1024U*1024U/32U){puts("ERROR chirp replay size");return;}
    chirp_state *s=(chirp_state*)storage;
    cached_algorithm();
    if(chirp_init(s,mapping)){Xil_DCacheDisable();puts("ERROR chirp initialization");return;}
    tx_head=tx_tail=tx_dropped=0;
    printf("CHIRP_REPLAY_START frames=%lu ignored_tail=%lu state_bytes=%lu\r\n",(unsigned long)frames,
        (unsigned long)(frames%CHIRP_PACKET),(unsigned long)chirp_state_size());
    XTime start=tick();unsigned results=0,valid=0,failed=0;
    for(uint32_t offset=0;offset+CHIRP_PACKET<=frames;offset+=CHIRP_PACKET) {
        volatile const uint32_t *src=(volatile const uint32_t*)(BUFFER_ADDR+offset*32U);
        for(unsigned i=0;i<CHIRP_PACKET;i++)for(unsigned j=0;j<8;j++)packet[i][j]=src[i*8+j];
        if(chirp_feed(s,packet)){failed=1;break;}
        chirp_service(s,10000);
        chirp_result r;
        if(chirp_take_result(s,&r)) {
            results++;valid+=r.status==CHIRP_OK||r.status==CHIRP_ZENITH;
            show_result(&r);
            XTime before=tick();while(tx_head!=tx_tail&&tick()-before<COUNTS_PER_SECOND)uart_service();
        }
    }
    XTime elapsed=tick()-start;Xil_DCacheDisable();
    printf("CHIRP_REPLAY_END results=%u valid=%u failed=%u elapsed_ms=%.1f\r\n",results,valid,failed,1000.0*elapsed/COUNTS_PER_SECOND);
}
void chirp_stream(const uint8_t mapping[7]) {
    if(rd(LED,8)!=0x4c454431U){puts("ERROR chirp requires LED1 PL build");return;}
    chirp_state *s=(chirp_state*)storage;
    wr(CAP,0,0);wr(DMA,CTRL,4);led_blank();
    XTime start=tick();
    while(rd(DMA,CTRL)&4U)if(tick()-start>COUNTS_PER_SECOND){puts("ERROR chirp DMA reset");return;}
    /* AMD's section API flushes D-cache and invalidates TLBs. Mark the reserved
     * DMA DDR region normal noncached before enabling cached algorithm RAM.
     * Legacy capture commands continue with D/L2 caches disabled on return. */
    cached_algorithm();
    if(chirp_init(s,mapping)){Xil_DCacheDisable();puts("ERROR chirp initialization");return;}
    tx_head=tx_tail=tx_dropped=0;
    const led_config config={LED_FIRST_INDEX,LED_CHAIN_REVERSED,LED_FAR_DBFS,LED_NEAR_DBFS};
    amp_mode(1);
    printf("CHIRP_START fs=%.6f band=500:6000 pulse_ms=20 period_ms=300 q=stop mapping=verified_identity\r\n",CHIRP_FS);
    printf("LED relative_strength_only far_dbfs=%.1f near_dbfs=%.1f first=%d reversed=%d physical_index_unverified=1\r\n",
        config.far_dbfs,config.near_dbfs,config.first_index,config.reversed);
    wr(CAP,4,0xffffffffU);wr(DMA,CTRL,1);arm(0);wr(CAP,0,1);
    unsigned active=0,results=0,accepted_results=0;uint64_t frames=0;
    const char *error=NULL;
    chirp_result latest={0};latest.status=CHIRP_BAD_INPUT;latest.elevation_deg=NAN;
    XTime packet_start=tick(),last_result=packet_start,last_led=0,max_feed=0,max_search=0,max_format=0;
    XTime stream_start=packet_start,work_ticks=0;
    for(;;) {
        if(XUartPs_IsReceiveData(UART)){
            unsigned char command=XUartPs_RecvByte(UART);
            if(command=='q')break;
            if(command=='v')amp_mode(0);else if(command=='h')amp_mode(1);
        }
        XTime now=tick();uint32_t status=rd(DMA,STATUS);
        if(status&0x770U){error="DMA status";break;}
        if(now-packet_start>2*COUNTS_PER_SECOND){error="DMA timeout";break;}
        if(rd(CAP,16)){error="PL dropped frames";break;}
        if(status&0x1000U) {
            if(rd(DMA,LENGTH)!=PACKET_BYTES){error="DMA packet length";break;}
            unsigned complete=active;active^=1;arm(active);packet_start=now;
            __asm__ volatile("dsb sy" ::: "memory");
            volatile const uint32_t *src=(volatile const uint32_t*)(BUFFER_ADDR+complete*PACKET_BYTES);
            for(unsigned i=0;i<CHIRP_PACKET;i++)for(unsigned j=0;j<8;j++)packet[i][j]=src[i*8+j];
            if(!frames&&packet[0][7]!=2048U){error="first frame sequence";break;}
            int rc=chirp_feed(s,packet);frames+=CHIRP_PACKET;
            if(!rc)amp_audio(packet);
            XTime elapsed=tick()-now;work_ticks+=elapsed;if(elapsed>max_feed)max_feed=elapsed;
            if(rc){error="frame sequence/padding";break;}
            /* A compute overrun may already have filled the next packet; the
             * next loop services it before doing any more search work. */
        } else {
            XTime before=tick();chirp_service(s,SEARCH_BATCH);
            XTime elapsed=tick()-before;work_ticks+=elapsed;if(elapsed>max_search)max_search=elapsed;
        }
        chirp_result r;
        if(chirp_take_result(s,&r)) {
            XTime before=tick();latest=r;last_result=before;results++;
            accepted_results+=r.status==CHIRP_OK||r.status==CHIRP_ZENITH;
            show_result(&r);last_led=0;
            amp_result(&r,before/(COUNTS_PER_SECOND/1000));
            XTime elapsed=tick()-before;work_ticks+=elapsed;if(elapsed>max_format)max_format=elapsed;
            if(r.status==CHIRP_OVERRUN){error="search cannot keep up";break;}
        }
        now=tick();
        if(now-last_led>COUNTS_PER_SECOND/10) {
            uint32_t pixels[12];double age=latest.latency_frames+(double)(now-last_result)*CHIRP_FS/COUNTS_PER_SECOND;
            led_ring_render(&latest,age>UINT32_MAX?UINT32_MAX:(uint32_t)age,&config,pixels);
            led_refresh(pixels);last_led=now;
        }
        uart_service();
    }
    uint32_t drops=rd(CAP,16),count=rd(CAP,12);
    XTime stream_elapsed=tick()-stream_start;
    wr(CAP,0,0);wr(DMA,CTRL,4);led_blank();Xil_DCacheDisable();
    amp_mode(1);
    /* Acquisition is stopped; bounded drain preserves complete pending lines. */
    start=tick();while(tx_head!=tx_tail&&tick()-start<COUNTS_PER_SECOND/2)uart_service();
    printf("CHIRP_END reason=%s frames=%llu accepted=%lu drops=%lu results=%u valid=%u log_dropped=%u feed_max_us=%.1f search_batch_max_us=%.1f format_max_us=%.1f core0_work_percent=%.1f\r\n",
        error?error:"user_stop",(unsigned long long)frames,(unsigned long)count,(unsigned long)drops,results,accepted_results,tx_dropped,
        1e6*(double)max_feed/COUNTS_PER_SECOND,1e6*(double)max_search/COUNTS_PER_SECOND,1e6*(double)max_format/COUNTS_PER_SECOND,
        stream_elapsed?100.0*(double)work_ticks/stream_elapsed:0.0);
    amp_report();
}
