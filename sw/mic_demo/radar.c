#include "radar.h"
#include "radar_assets.h"
#include "led_ring.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#define PI 3.14159265358979323846f
static uint32_t frame[RADAR_WORDS];
static chirp_result latest;
static uint64_t event_ms;
typedef struct {int x,y;uint64_t at;} trace_point;
static trace_point trace[24];static unsigned trace_count;
static float spectrum[64],re[256],im[256],window[256],tr[128],ti[128],window_sum;
static void pixel(int x,int y,unsigned c){
    if((unsigned)x>=RADAR_WIDTH||(unsigned)y>=RADAR_HEIGHT)return;
    unsigned p=(unsigned)(y*RADAR_WIDTH+x),shift=(p&7)*4;
    frame[p>>3]=(frame[p>>3]&~(15U<<shift))|((c&15U)<<shift);
}
static void rect(int x,int y,int w,int h,unsigned c){for(int j=y;j<y+h;j++)for(int i=x;i<x+w;i++)pixel(i,j,c);}
static void line(int x,int y,int xx,int yy,unsigned c){
    int dx=xx>x?xx-x:x-xx,sx=x<xx?1:-1,dy=yy>y?y-yy:yy-y,sy=y<yy?1:-1,err=dx+dy;
    for(;;){pixel(x,y,c);if(x==xx&&y==yy)break;int e=2*err;if(e>=dy){err+=dy;x+=sx;}if(e<=dx){err+=dx;y+=sy;}}
}
static void circle(int x,int y,int radius,unsigned c){
    for(int j=-radius;j<=radius;j++)for(int i=-radius;i<=radius;i++)if(i*i+j*j<=radius*radius)pixel(x+i,y+j,c);
}
static void text(int x,int y,const char *s,unsigned c,int scale){
    for(;*s;s++,x+=8*scale){unsigned ch=(unsigned char)*s;if(ch<32||ch>127)ch='?';
        for(int row=0;row<14;row++)for(int col=0;col<8;col++)if(radar_glyphs[ch-32][row]&(1U<<col))rect(x+col*scale,y+row*scale,scale,scale,c);
    }
}
void radar_project(float az,float el,int*x,int*y){
    float a=(az+25)*PI/180,e=el*PI/180;
    *x=(int)lroundf(236+158*cosf(e)*cosf(a));
    *y=(int)lroundf(213-158*(cosf(e)*sinf(a)*.36f+sinf(e)*.95f));
}
void radar_init(void){
    memset(&latest,0,sizeof latest);latest.status=CHIRP_BAD_INPUT;latest.level_dbfs=NAN;
    latest.azimuth_deg=latest.elevation_deg=NAN;trace_count=0;event_ms=0;
    memset(spectrum,0,sizeof spectrum);window_sum=0;
    for(int i=0;i<256;i++){window[i]=.5f-.5f*cosf(2*PI*i/255);window_sum+=window[i];}
    for(int i=0;i<128;i++){tr[i]=cosf(-2*PI*i/256);ti[i]=sinf(-2*PI*i/256);}
}
static int result_valid(const chirp_result*r){
    if(!isfinite(r->elevation_deg)||r->elevation_deg<0||r->elevation_deg>90||!isfinite(r->level_dbfs))return 0;
    return r->status==CHIRP_ZENITH||(r->status==CHIRP_OK&&r->azimuth_valid&&isfinite(r->azimuth_deg));
}
void radar_result(const chirp_result*r,uint64_t now){
    if(!r)return;
    uint64_t latency=(uint64_t)(r->latency_frames*1000.0/CHIRP_FS);
    latest=*r;event_ms=now>=latency?now-latency:0;
    if(!result_valid(r)||latency>750||latency>now){
        if(latency>750||latency>now)latest.status=CHIRP_BAD_INPUT;
        trace_count=0;return;
    }
    if(trace_count==24){memmove(trace,trace+1,23*sizeof *trace);trace_count--;}
    trace_point *p=&trace[trace_count++];p->at=event_ms;
    radar_project(r->status==CHIRP_ZENITH?0:r->azimuth_deg,r->status==CHIRP_ZENITH?90:r->elevation_deg,&p->x,&p->y);
}
void radar_spectrum(const int32_t mono[CHIRP_PACKET]){
    // Center microphone M6; Hann FFT amplitude, fixed -95 .. -20 dBFS scale.
    for(int i=0;i<256;i++){re[i]=mono[i]*(1.f/2147483648.f)*window[i];im[i]=0;}
    for(int i=1,j=0;i<256;i++){int bit=128;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){float t=re[i];re[i]=re[j];re[j]=t;}}
    for(int n=2;n<=256;n*=2)for(int i=0;i<256;i+=n)for(int j=0;j<n/2;j++){
        int k=j*256/n,u=i+j,v=u+n/2;float vr=re[v]*tr[k]-im[v]*ti[k],vi=re[v]*ti[k]+im[v]*tr[k];
        re[v]=re[u]-vr;im[v]=im[u]-vi;re[u]+=vr;im[u]+=vi;
    }
    for(int b=0;b<64;b++){
        float power=0;for(int k=b*2;k<b*2+2;k++){float p=re[k]*re[k]+im[k]*im[k];if(p>power)power=p;}
        float db=10*log10f(fmaxf(1e-20f,4*power/(window_sum*window_sum)));
        float value=fminf(1,fmaxf(0,(db+95)/75));spectrum[b]=fmaxf(value,spectrum[b]*.90f);
    }
}
const uint32_t *radar_render(uint64_t now){
    unsigned char *dst=(unsigned char*)frame;
    for(unsigned i=0;i<sizeof radar_background_rle/sizeof *radar_background_rle;i++){
        unsigned n=radar_background_rle[i]>>8;memset(dst,radar_background_rle[i]&255,n);dst+=n;
    }
    uint64_t age=now>=event_ms?now-event_ms:UINT64_MAX;
    int valid=result_valid(&latest)&&age<=750;
    unsigned accent=latest.status==CHIRP_ZENITH?11:9;
    text(499,15,valid?(latest.status==CHIRP_ZENITH?"ZENITH":"TRACKING"):"WAITING",valid?accent:3,1);
    char value[24];
    if(valid&&latest.azimuth_valid)snprintf(value,sizeof value,"%03.0f",latest.azimuth_deg);else strcpy(value,"---");
    text(499,73,value,valid?5:3,2);text(551,88,"deg",3,1);
    if(valid)snprintf(value,sizeof value,"%02.0f",latest.elevation_deg);else strcpy(value,"--");
    text(499,140,value,valid?5:3,2);text(539,155,"deg",3,1);
    if(isfinite(latest.level_dbfs)&&age<=750)snprintf(value,sizeof value,"%5.1f dBFS",latest.level_dbfs);else strcpy(value,"  -- dBFS");
    text(499,213,value,4,1);rect(500,237,117,4,2);
    float strength=isfinite(latest.level_dbfs)?fminf(1,fmaxf(0,(latest.level_dbfs-LED_FAR_DBFS)/(LED_NEAR_DBFS-LED_FAR_DBFS))):0;
    if(age<=750)rect(500,237,(int)(117*strength),4,valid?9:3);
    if(valid){
        for(unsigned i=1;i<trace_count;i++)if(now>=trace[i-1].at&&now-trace[i-1].at<3000){
            unsigned color=now-trace[i].at<1000?8:now-trace[i].at<2000?7:6;
            line(trace[i-1].x,trace[i-1].y,trace[i].x,trace[i].y,color);
        }
        int x,y,bx,by;float az=latest.status==CHIRP_ZENITH?0:latest.azimuth_deg,el=latest.status==CHIRP_ZENITH?90:latest.elevation_deg;
        radar_project(az,el,&x,&y);radar_project(az,0,&bx,&by);
        bx=236+(int)((bx-236)*cosf(el*PI/180));by=213+(int)((by-213)*cosf(el*PI/180));
        for(int yy=y;yy<=by;yy+=5)line(x,yy,x,yy+1,latest.status==CHIRP_ZENITH?10:6);
        line(236,213,x,y,accent);line(237,213,x+1,y,latest.status==CHIRP_ZENITH?10:7);
        circle(x,y,8,latest.status==CHIRP_ZENITH?10:6);circle(x,y,5,accent);circle(x,y,3,0);
        circle(x,y,2,strength>.2f?accent:7);
    }else if(trace_count)trace_count=0;
    // Same production LED mapping; no independently invented screen bearing.
    const led_config config={0,0,LED_FAR_DBFS,LED_NEAR_DBFS};uint32_t lamps[12];
    uint32_t age_frames=age>100000?UINT32_MAX:(uint32_t)(age*CHIRP_FS/1000);
    led_ring_render(&latest,age_frames,&config,lamps);
    for(int i=0;i<12;i++){
        int x=(int)lroundf(558+27*sinf(i*PI/6)),y=(int)lroundf(305-27*cosf(i*PI/6));
        unsigned color=2,g=(lamps[i]>>8)&255,b=(lamps[i]>>16)&255;
        if(g)color=g>170?9:g>85?8:7;
        if(b)color=b>100?11:10;
        circle(x,y,3,color);
    }
    text(547,299,"6+1",3,1);
    for(int i=0;i<64;i++){int h=(int)lroundf(18*spectrum[i]);if(h)rect(24+i*6,327-h,4,h,11);}
    return frame;
}
