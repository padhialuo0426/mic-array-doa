/* AX7020 loss-detecting capture and single-source upper-hemisphere DOA. */
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include "xil_io.h"
#include "xil_cache.h"
#include "xiltimer.h"
#include "xuartps_hw.h"
#include "doa.h"
#include "realtime.h"
#include "amp_control.h"

#define CAP 0x43c00000U
#define DMA 0x40400000U
#define UART 0xe0001000U
#define BUFFER_ADDR 0x10000000U
#define FIVE_SECOND_FRAMES 81380U
#define TWENTY_SECOND_FRAMES 325521U
#define MINUTE_FRAMES 976563U
#define CAPTURE_BUFFER_BYTES (32U*1024U*1024U)
#if MINUTE_FRAMES > CAPTURE_BUFFER_BYTES/32U
#error "Minute capture exceeds reserved DDR capture region"
#endif
#define PACKET 256U
#define CTRL 0x30U
#define STATUS 0x34U
#define DEST 0x48U
#define LENGTH 0x58U
static volatile uint32_t *const samples=(volatile uint32_t *)BUFFER_ADDR;
static uint32_t saved_frames;
static int saved_synthetic;
/* Initialized ELF data: a JTAG loader may set this to 0 before entry to keep
 * manual UART commands and debugger-controlled CPU1 startup. SD uses 1. */
volatile uint32_t mic_boot_autostart=1U;
static doa_state estimator;
static double tone_frequency=1000.0;
/* Physical M0..M6 -> I2S decoded channel. Identity verified by the complete
   localized M0..M6 recording; M6 is central, M0..M5 clockwise on the face. */
static const uint8_t physical_to_raw[7]={0,1,2,3,4,5,6};

static uint32_t rd(uint32_t base,uint32_t off) { return Xil_In32(base+off); }
static void wr(uint32_t base,uint32_t off,uint32_t value) { Xil_Out32(base+off,value); }
static int expired(XTime start,unsigned seconds) {
    XTime now; XTime_GetTime(&now);
    return now-start>(XTime)COUNTS_PER_SECOND*seconds;
}
static int capture(uint32_t frames,int synthetic) {
    XTime start,end;
    saved_frames=0;
    if(!frames || frames>CAPTURE_BUFFER_BYTES/32U) {puts("ERROR capture size");return -1;}
    wr(CAP,0,0);
    wr(DMA,CTRL,4);
    XTime_GetTime(&start);
    while(rd(DMA,CTRL)&4) if(expired(start,1)) {puts("ERROR DMA reset timeout");return -1;}
    // D-cache is disabled for this bring-up program: DDR is shared directly
    // with DMA and OpenOCD, with no dirty/stale cache lines to transfer.
    for(uint32_t i=0;i<frames*8;i++) samples[i]=0xdeadbeefU;
    __asm__ volatile("dsb sy" ::: "memory");
    wr(CAP,4,frames);
    wr(DMA,CTRL,1);
    printf("CAPTURE_START mode=%s frames=%lu seconds=%.6f warmup_frames=%u\r\n",synthetic?"test":"mic",(unsigned long)frames,(double)frames/DOA_FS,synthetic?0U:2048U);
    XTime_GetTime(&start);
    for(uint32_t offset=0;offset<frames;offset+=PACKET) {
        uint32_t count=frames-offset;
        if(count>PACKET) count=PACKET;
        uint32_t bytes=count*32;
        wr(DMA,STATUS,0x1000);
        wr(DMA,DEST,BUFFER_ADDR+offset*32);
        wr(DMA,LENGTH,bytes);
        if(offset==0) wr(CAP,0,synthetic ? 3 : 1);
        XTime packet_start;XTime_GetTime(&packet_start);
        for(;;) {
            uint32_t status=rd(DMA,STATUS);
            if(status&0x770U) {printf("ERROR DMA status=%08lx packet=%lu\r\n",(unsigned long)status,(unsigned long)(offset/PACKET));goto fail;}
            if(status&0x1000U) break;
            if(expired(packet_start,2)) {printf("ERROR DMA timeout status=%08lx accepted=%lu\r\n",(unsigned long)status,(unsigned long)rd(CAP,12));goto fail;}
        }
        if(rd(DMA,LENGTH)!=bytes) {printf("ERROR DMA length got=%lu expected=%lu\r\n",(unsigned long)rd(DMA,LENGTH),(unsigned long)bytes);goto fail;}
    }
    XTime_GetTime(&end);
    __asm__ volatile("dsb sy" ::: "memory");
    uint32_t accepted=rd(CAP,12),drops=rd(CAP,16),empty=rd(CAP,24),status=rd(CAP,8);
    wr(CAP,0,0);
    uint32_t gaps=0,padding=0,pattern=0;
    static const uint32_t bases[7]={0x123456,0xfedcba,0x800000,0x7fffff,0xaaaaaa,0x555555,0x800001};
    for(uint32_t f=0;f<frames;f++) {
        uint32_t seq=samples[f*8+7];
        if(f && seq!=samples[(f-1)*8+7]+1) gaps++;
        for(unsigned ch=0;ch<7;ch++) {
            uint32_t value=samples[f*8+ch];
            if(value&255) padding++;
            if(synthetic && value!=((bases[ch]+seq)<<8)) pattern++;
        }
    }
    printf("CAPTURE mode=%s frames=%lu bytes=%lu addr=0x%08lx ms=%.3f\r\n",synthetic?"test":"mic",(unsigned long)frames,(unsigned long)(frames*32),(unsigned long)BUFFER_ADDR,1000.0*(double)(end-start)/(COUNTS_PER_SECOND));
    printf("CHECK accepted=%lu drops=%lu gaps=%lu padding=%lu pattern=%lu empty_left_nonzero=%lu first=%lu last=%lu done=%lu\r\n",(unsigned long)accepted,(unsigned long)drops,(unsigned long)gaps,(unsigned long)padding,(unsigned long)pattern,(unsigned long)empty,(unsigned long)samples[7],(unsigned long)samples[(frames-1)*8+7],(unsigned long)((status>>1)&1));
    if(accepted!=frames || drops || gaps || padding || pattern || !(status&2) || samples[7]!=(synthetic?0:2048)) {puts("ERROR capture integrity");return -1;}
    saved_frames=frames;
    saved_synthetic=synthetic;
    if(synthetic) puts("SELFTEST PASS: all 7 words, sequence, packet and tail lengths");
    return 0;
fail:
    wr(CAP,0,0);wr(DMA,CTRL,4);return -1;
}

static void statistics(void) {
    puts("CHANNEL,min,max,dc,ac_rms,peak,zero,changed,clipped");
    for(unsigned ch=0;ch<7;ch++) {
        int32_t minimum=8388607,maximum=-8388608,previous=0;
        int64_t sum=0;double square=0;
        uint32_t zeros=0,changes=0,clipped=0,peak=0;
        for(uint32_t f=0;f<saved_frames;f++) {
            int32_t value=(int32_t)samples[f*8+ch]>>8;
            uint32_t magnitude=value<0 ? (uint32_t)-value : (uint32_t)value;
            if(value<minimum) minimum=value;
            if(value>maximum) maximum=value;
            if(magnitude>peak) peak=magnitude;
            /* A minute of full-scale 24-bit samples exceeds uint64_t for
               the sum of squares. Keep the energy accumulator in double. */
            sum+=value;square+=(double)value*value;
            zeros+=value==0;changes+=f && value!=previous;clipped+=magnitude>=8380000;
            previous=value;
        }
        double dc=(double)sum/saved_frames;
        double variance=(double)square/saved_frames-dc*dc;
        printf("M%u,%ld,%ld,%.2f,%.2f,%lu,%lu,%lu,%lu\r\n",ch,(long)minimum,(long)maximum,dc,sqrt(variance>0?variance:0),(unsigned long)peak,(unsigned long)zeros,(unsigned long)changes,(unsigned long)clipped);
    }
    puts("Activity alone does not certify a microphone: compare quiet and sound captures.");
}

static int estimator_init(void) {
    return doa_init(&estimator,tone_frequency,DOA_SETTLE_FRAMES) ||
           doa_set_mapping(&estimator,physical_to_raw);
}
static void print_direction(const doa_result *r) {
    printf("DOA seq=%lu status=%s az=",(unsigned long)r->frame_sequence,doa_status_name(r->status));
    if(r->azimuth_valid) printf("%.3f",r->azimuth_deg);else printf("NA");
    printf(" el=");
    if(isfinite(r->elevation_deg)) printf("%.3f",r->elevation_deg);else printf("NA");
    printf(" db=%.2f coh=%.5f fit=%.5f\r\n",r->tone_dbfs,r->coherence,r->fit);
}
static void analyze_saved(void) {
    if(saved_synthetic || saved_frames<DOA_SETTLE_FRAMES+DOA_WINDOW+8*DOA_HOP) {
        puts("ERROR DOA needs a 5-second microphone capture (d)");return;
    }
    if(estimator_init()) {puts("ERROR DOA initialization");return;}
    printf("ANALYZE source=DDR frames=%lu tone=%.0f mapping=verified_identity\r\n",(unsigned long)saved_frames,tone_frequency);
    XTime start,end;XTime_GetTime(&start);
    unsigned results=0;
    for(uint32_t f=0;f<saved_frames;f++) {
        uint32_t frame[8];doa_result result;
        for(unsigned j=0;j<8;j++)frame[j]=samples[f*8+j];
        int rc=doa_feed(&estimator,frame,&result);
        if(rc<0) {printf("ERROR DOA frame=%lu\r\n",(unsigned long)f);return;}
        if(rc) {print_direction(&result);results++;}
    }
    XTime_GetTime(&end);
    printf("ANALYZE_END results=%u ms=%.3f\r\n",results,1000.0*(double)(end-start)/(COUNTS_PER_SECOND));
}
static void dma_arm(uint32_t address) {
    wr(DMA,STATUS,0x1000);wr(DMA,DEST,address);wr(DMA,LENGTH,PACKET*32);
}
static void stream_doa(void) {
    if(estimator_init()) {puts("ERROR DOA initialization");return;}
    saved_frames=0;
    wr(CAP,0,0);wr(DMA,CTRL,4);
    XTime start;XTime_GetTime(&start);
    while(rd(DMA,CTRL)&4) if(expired(start,1)) {puts("ERROR DMA reset timeout");return;}
    puts("STREAM tone selected below; upper hemisphere; q=stop; mapping=verified_identity");
    printf("STREAM_CONFIG tone=%.0f fs=%.6f rate=%.6f settle=%lu\r\n",tone_frequency,DOA_FS,DOA_FS/(3*DOA_HOP),(unsigned long)DOA_SETTLE_FRAMES);
    wr(CAP,4,0xffffffffU);wr(DMA,CTRL,1);
    dma_arm(BUFFER_ADDR);wr(CAP,0,1);
    unsigned active=0,results=0,failed=0;
    uint32_t frames=0;
    XTime packet_start,max_compute=0,max_service=0;XTime_GetTime(&packet_start);
    for(;;) {
        if(XUartPs_IsReceiveData(UART) && XUartPs_RecvByte(UART)=='q') break;
        uint32_t status=rd(DMA,STATUS);
        if((status&0x770U) || expired(packet_start,2)) {
            printf("ERROR STREAM DMA status=%08lx\r\n",(unsigned long)status);failed=1;break;
        }
        if(!(status&0x1000U)) continue;
        if(rd(DMA,LENGTH)!=PACKET*32) {puts("ERROR STREAM packet length");failed=1;break;}
        unsigned complete=active;active^=1;
        /* Arm the other DDR buffer before consuming this one. The PL clock
           and receiver remain enabled across every packet. */
        dma_arm(BUFFER_ADDR+active*PACKET*32);
        XTime work_start,compute_end,work_end;XTime_GetTime(&work_start);
        packet_start=work_start;
        __asm__ volatile("dsb sy" ::: "memory");
        doa_result result;int emitted=0;
        for(unsigned f=0;f<PACKET;f++) {
            uint32_t frame[8];
            for(unsigned j=0;j<8;j++)frame[j]=samples[complete*PACKET*8+f*8+j];
            if(frames==0 && frame[7]!=2048) {puts("ERROR STREAM first sequence");failed=1;break;}
            int rc=doa_feed(&estimator,frame,&result);
            if(rc<0) {puts("ERROR STREAM frame sequence or padding");failed=1;break;}
            frames++;emitted+=rc;
        }
        XTime_GetTime(&compute_end);
        if(compute_end-work_start>max_compute) max_compute=compute_end-work_start;
        if(failed) break;
        if(emitted) {print_direction(&result);results++;}
        XTime_GetTime(&work_end);
        if(work_end-work_start>max_service) max_service=work_end-work_start;
        if(rd(CAP,16)) {puts("ERROR STREAM dropped frames");failed=1;break;}
    }
    uint32_t drops=rd(CAP,16),accepted=rd(CAP,12);
    wr(CAP,0,0);wr(DMA,CTRL,4);
    printf("STREAM_END frames=%lu accepted=%lu drops=%lu results=%u failed=%u compute_max_us=%.1f service_max_us=%.1f\r\n",(unsigned long)frames,(unsigned long)accepted,(unsigned long)drops,results,failed,
           1e6*(double)max_compute/(COUNTS_PER_SECOND),1e6*(double)max_service/(COUNTS_PER_SECOND));
}

int main(void) {
    // ICacheEnable also enables the shared PL310 L2. Disable data caches LAST
    // so HP0 writes cannot be hidden by L2, even with the L1 D-cache off.
    Xil_ICacheEnable();Xil_DCacheDisable();
    setvbuf(stdout,NULL,_IONBF,0);
    puts("\r\nMICARRAY DEMO v5 AX7020: CPU0 capture/DOA + CPU1 radar/FFT + PL HDMI");
    printf("BOOT mode=%lu autostart=%lu\r\n",(unsigned long)(Xil_In32(0xf800025cU)&7U),
           (unsigned long)mic_boot_autostart);
    printf("CACHE L2_CTRL=%lu (must be 0)\r\n",(unsigned long)Xil_In32(0xf8f02100U));
    if(Xil_In32(0xf8f02100U)&1U) {puts("ERROR L2 cache must be disabled");for(;;);}
    printf("PL id=%08lx divider=%lu packet=%lu\r\n",(unsigned long)rd(CAP,32),(unsigned long)rd(CAP,28),(unsigned long)rd(CAP,36));
    if(rd(CAP,32)!=0x4d494331 || rd(CAP,28)!=96 || rd(CAP,36)!=256) {puts("ERROR incompatible PL");for(;;);}
    amp_init();
    int startup_ok=capture(770,1)==0 && capture(16384,0)==0;
    if(startup_ok)statistics();
    if(mic_boot_autostart){
        if(!startup_ok)puts("ERROR autostart blocked by capture selftest");
        else if(amp_start_secondary()){
            puts("ERROR CPU1 startup failed; autostart stopped");amp_report();
        }else{
            puts("AUTOSTART CPU1_READY: starting chirp DOA, LED and HDMI");
            amp_report();saved_frames=0;chirp_stream(physical_to_raw);
        }
    }
    for(;;) {
        printf("READY frames=%lu tone=%.0f | c=1s d=5s e=20s m=60s t=test s=stats a=analyze r=tone_stream b=chirp_LED p=chirp_replay q=stop v=HDMI_bars h=HDMI_radar i=AMP_stats 1=1000Hz 2=2610Hz\r\n",(unsigned long)saved_frames,tone_frequency);
        unsigned char c;
        do { c=XUartPs_RecvByte(UART); } while(c=='\r' || c=='\n');
        if(c=='t') capture(770,1);
        else if(c=='c' || c=='d' || c=='e' || c=='m') {
            uint32_t frames=c=='m'?MINUTE_FRAMES:(c=='d'?FIVE_SECOND_FRAMES:16384U);
            if(c=='e') frames=TWENTY_SECOND_FRAMES;
            if(capture(frames,0)==0) statistics();
        }
        else if(c=='s' && saved_frames) statistics();
        else if(c=='a') analyze_saved();
        else if(c=='r') stream_doa();
        else if(c=='b') {saved_frames=0;chirp_stream(physical_to_raw);}
        else if(c=='p' && saved_frames && !saved_synthetic) chirp_replay(saved_frames,physical_to_raw);
        else if(c=='v')amp_mode(0);
        else if(c=='h')amp_mode(1);
        else if(c=='i')amp_report();
        else if(c=='1' || c=='2') tone_frequency=c=='1'?1000.0:2610.0;
    }
}
