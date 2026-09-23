/* Portable streaming chirp matched filter + first-arrival gated SRP-PHAT.
 * No allocation or hardware I/O. Do not call feed/service concurrently.
 * The finite overlap filter and local sinc interpolation approximate the
 * full-record FFT reference in tools/broadband_doa.py; regression tests compare
 * physical signals, strong reflections, and saved recordings independently.
 */
#include "chirp.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>
#define PI 3.14159265358979323846f
#define FFT_N 1024
#define FFT_MAX 8192
#define RING 4096
#define MASK (RING-1)
#define LEN 326
#define UP 8
#define BINS 44
/* A 70 ms search interval contains < 570 isolated sample-grid maxima. */
#define CANDIDATES 600
typedef struct {float re,im;} cx;
typedef struct {int64_t index; float height;} peak;
struct chirp_state {
    cx twiddle[FFT_MAX/2], work[FFT_MAX], kernel[FFT_N];
    cx h[7][RING], spec[3][7][BINS];
    peak candidates[CANDIDATES], accepted[CANDIDATES];
    int32_t raw[7][RING];
    float env[RING], bound[1024], sinc[UP][32], xy[7][2];
    float energy, floor, event_floor, az[3], el[3], quality[3];
    float best_power, best_az, best_el, refine_az, refine_el;
    uint8_t mapping[7];
    uint32_t previous, have_sequence, fatal, ready, busy, gate, node, refine;
    uint64_t seen;
    int64_t h_first, h_end, trigger, dead_until;
    int nbin[3], firstbin[3], size[3];
    chirp_result result;
};
_Static_assert(sizeof(struct chirp_state)<=CHIRP_STORAGE_BYTES,"Increase chirp storage");
static cx mul(cx a,cx b) {cx r={a.re*b.re-a.im*b.im,a.re*b.im+a.im*b.re};return r;}
static float mag(cx a) {return hypotf(a.re,a.im);}
static void fft(chirp_state *s,int n,int inverse) {
    cx *a=s->work;
    for(int i=1,j=0;i<n;i++) {
        int bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;
        if(i<j) {cx t=a[i];a[i]=a[j];a[j]=t;}
    }
    for(int len=2;len<=n;len*=2) for(int i=0;i<n;i+=len) for(int j=0;j<len/2;j++) {
        cx w=s->twiddle[j*(FFT_MAX/len)];if(inverse)w.im=-w.im;
        cx u=a[i+j],v=mul(a[i+j+len/2],w);
        a[i+j]=(cx){u.re+v.re,u.im+v.im};a[i+j+len/2]=(cx){u.re-v.re,u.im-v.im};
    }
    if(inverse)for(int i=0;i<n;i++){a[i].re/=n;a[i].im/=n;}
}
static float taper(int i,int n,float alpha) {
    int edge=(int)(alpha*n/2);if(edge<1)edge=1;
    if(i>=n-edge)i=n-1-i;
    return i<edge?.5f-.5f*cosf(PI*i/edge):1.f;
}
static void chirp_kernel(chirp_state *s,int n) {
    memset(s->work,0,n*sizeof(cx));
    for(int i=0;i<LEN;i++) {
        double t=i/CHIRP_FS;
        s->work[i].re=(float)sin(2.0*3.141592653589793*(500*t+5500*t*t/.04))*taper(i,LEN,.1f);
    }
    fft(s,n,0);
}
size_t chirp_state_size(void) {return sizeof(chirp_state);}
int chirp_init(chirp_state *s,const uint8_t mapping[7]) {
    if(!s||!mapping)return -1;
    unsigned bits=0;for(int i=0;i<7;i++){if(mapping[i]>=7 || (bits&(1U<<mapping[i])))return -1;bits|=1U<<mapping[i];}
    memset(s,0,sizeof(*s));memcpy(s->mapping,mapping,7);
    s->h_first=INT64_MAX;s->h_end=-1;s->trigger=-1;s->dead_until=-1;s->floor=1e-7f;
    for(int i=0;i<FFT_MAX/2;i++)s->twiddle[i]=(cx){cosf(-2*PI*i/FFT_MAX),sinf(-2*PI*i/FFT_MAX)};
    for(int m=0;m<6;m++){s->xy[m][0]=.04f*cosf(-m*PI/3);s->xy[m][1]=.04f*sinf(-m*PI/3);}
    chirp_kernel(s,FFT_N);
    for(int k=0;k<FFT_N;k++) {
        float f=(float)(k*CHIRP_FS/FFT_N);
        s->kernel[k]=(f>=500&&f<=6000)?(cx){2*s->work[k].re,-2*s->work[k].im}:(cx){0,0};
    }
    chirp_kernel(s,FFT_MAX);
    for(int k=0;k<FFT_MAX;k++) {
        float f=(float)(k*CHIRP_FS/FFT_MAX);
        float a=s->work[k].re,b=s->work[k].im;
        s->work[k]=(f>=500&&f<=6000)?(cx){2*(a*a+b*b),0}:(cx){0,0};
    }
    fft(s,FFT_MAX,1);s->energy=s->work[0].re;
    for(int i=0;i<1024;i++)for(int j=-4;j<=4;j++) {
        float v=mag(s->work[(i+j+FFT_MAX)%FFT_MAX])/s->energy;
        if(v>s->bound[i])s->bound[i]=v;
    }
    for(int p=0;p<UP;p++)for(int j=0;j<32;j++) {
        float x=(float)p/UP-(j-15);
        s->sinc[p][j]=fabsf(x)<1e-7f?1.f:sinf(PI*x)/(PI*x)*sinf(PI*x/16)/(PI*x/16);
    }
    return 0;
}
static int cmpfloat(const void*a,const void*b){float x=*(const float*)a,y=*(const float*)b;return (x>y)-(x<y);}
static int cmppeak(const void*a,const void*b){float x=((const peak*)a)->height,y=((const peak*)b)->height;return (y>x)-(y<x);}
static float interp(chirp_state*s,int m,int64_t u) {
    int64_t base=u/UP;int p=(int)(u%UP);float v=0;
    for(int j=0;j<32;j++)v+=s->h[m][(base+j-15)&MASK].re*s->sinc[p][j];
    return v;
}
static void publish(chirp_state*s,unsigned status) {
    s->result.status=status;s->result.azimuth_valid=status==CHIRP_OK;
    s->result.latency_frames=(uint32_t)(s->previous-s->result.frame_sequence);
    if(status!=CHIRP_OK&&status!=CHIRP_ZENITH){s->result.azimuth_deg=NAN;s->result.elevation_deg=NAN;}
    else if(status==CHIRP_ZENITH)s->result.azimuth_deg=NAN;
    s->ready=1;s->busy=0;
}
static int start_event(chirp_state*s,int64_t stop) {
    /* Keep these arrays in state, not the bare-metal call stack. */
    peak *p=s->candidates,*accepted=s->accepted;int np=0,na=0;
    int64_t lo=s->trigger-(int64_t)(.03*CHIRP_FS),hi=stop-6;
    if(lo<s->h_first+16)lo=s->h_first+16;
    float strongest=0;
    for(int64_t i=lo;i<=hi;i++)if(s->env[i&MASK]>strongest)strongest=s->env[i&MASK];
    for(int64_t i=lo+1;i<hi;i++) {
        float v=s->env[i&MASK];
        if(v<=10*s->event_floor||v<.005f*strongest||v<=s->env[(i-1)&MASK]||v<s->env[(i+1)&MASK])continue;
        /* Local prominence suppresses noise riding a broad pulse. */
        float left=v,right=v;
        for(int j=1;j<=5;j++){left=fminf(left,s->env[(i-j)&MASK]);right=fminf(right,s->env[(i+j)&MASK]);}
        if(v-fmaxf(left,right)<fmaxf(3*s->event_floor,.005f*strongest))continue;
        if(np<CANDIDATES)p[np++]=(peak){i,v};
    }
    qsort(p,np,sizeof(peak),cmppeak);
    for(int i=0;i<np;i++) {
        float leakage=0;
        for(int j=0;j<na;j++) {
            int64_t d=llabs(p[i].index-accepted[j].index);
            if(d<1024)leakage+=1.5f*accepted[j].height*s->bound[d];
        }
        if(p[i].height>fmaxf(leakage,10*s->event_floor))accepted[na++]=p[i];
    }
    if(!na)return 0;
    peak first=accepted[0];for(int i=1;i<na;i++)if(accepted[i].index<first.index)first=accepted[i];
    if(s->busy||s->ready) {publish(s,CHIRP_OVERRUN);return 1;}
    int64_t begin=first.index*UP-(int64_t)lround(.0003*CHIRP_FS*UP);
    int64_t end=first.index*UP+(int64_t)lround(.00015*CHIRP_FS*UP);
    float local=0;
    for(int64_t i=begin;i<=end;i++)for(int m=0;m<7;m++)local=fmaxf(local,fabsf(interp(s,m,i)));
    int64_t onset=begin;int found=0;
    for(int64_t i=begin;i<=end&&!found;i++)for(int m=0;m<7;m++)if(fabsf(interp(s,m,i))>=.5f*local){onset=i;found=1;break;}
    memset(&s->result,0,sizeof(s->result));
    s->result.azimuth_deg=s->result.elevation_deg=NAN;
    s->result.frame_sequence=s->previous-(uint32_t)(s->seen-1-onset/UP);
    s->result.snr_db=20*log10f(first.height/s->event_floor);
    /* Median matched-pulse amplitude across channels, fixed dBFS scale. */
    float levels[7]={0};
    for(int m=0;m<7;m++)for(int64_t i=first.index-5;i<=first.index+5;i++)levels[m]=fmaxf(levels[m],mag(s->h[m][i&MASK])/s->energy);
    qsort(levels,7,sizeof(float),cmpfloat);s->result.level_dbfs=20*log10f(fmaxf(levels[3],1e-15f));
    int64_t raw_lo=onset/UP-17,raw_hi=onset/UP+LEN+17;
    if(raw_lo<0||raw_hi>=(int64_t)s->seen||raw_lo<(int64_t)s->seen-RING){publish(s,CHIRP_BAD_INPUT);return 1;}
    int clip=0,dead=0;
    for(int m=0;m<7;m++) {
        int32_t mn=INT32_MAX,mx=INT32_MIN;
        for(int64_t i=raw_lo;i<=raw_hi;i++){int32_t v=s->raw[m][i&MASK];if(v<mn)mn=v;if(v>mx)mx=v;if(v>=8380000||v<=-8380000)clip=1;}
        if(mx==mn)dead=1;
    }
    if(clip||dead){publish(s,clip?CHIRP_CLIPPED:CHIRP_CHANNEL_FAULT);return 1;}
    int pre=(int)lround(.0004*CHIRP_FS*UP);
    for(int g=0;g<3;g++) {
        /* central, shorter, longer gate */
        double post=g==0?.0006:(g==1?.0005:.0007);
        int n=pre+(int)lround(post*CHIRP_FS*UP),size=1;
        while(size<4*n)size*=2;
        s->size[g]=size;
        for(int m=0;m<7;m++) {
            memset(s->work,0,size*sizeof(cx));
            for(int i=0;i<n;i++)s->work[i].re=interp(s,m,onset-pre+i)*taper(i,n,.2f);
            fft(s,size,0);int count=0;
            for(int k=0;k<=size/2;k++) {
                double f=k*CHIRP_FS*UP/size;
                if(f<500||f>6000)continue;
                if(count==0)s->firstbin[g]=k;
                if(count>=BINS){publish(s,CHIRP_BAD_INPUT);return 1;}
                float a=fmaxf(mag(s->work[k]),1e-30f);
                s->spec[g][m][count++]=(cx){s->work[k].re/a,s->work[k].im/a};
            }
            s->nbin[g]=count;
        }
    }
    s->gate=0;s->node=0;s->refine=0;s->best_power=-1;s->busy=1;return 1;
}
int chirp_feed(chirp_state*s,const uint32_t words[CHIRP_PACKET][8]) {
    if(!s||!words||s->fatal)return -1;
    for(int i=0;i<CHIRP_PACKET;i++) {
        uint32_t seq=words[i][7];
        if(s->have_sequence&&seq!=s->previous+1U){s->fatal=1;publish(s,CHIRP_BAD_INPUT);return -1;}
        for(int m=0;m<7;m++) {
            uint32_t v=words[i][s->mapping[m]];
            if(v&255U){s->fatal=1;publish(s,CHIRP_BAD_INPUT);return -1;}
            s->raw[m][s->seen&MASK]=(int32_t)v>>8;
        }
        s->seen++;s->previous=seq;s->have_sequence=1;
    }
    if(s->seen<FFT_N)return 0;
    /* Valid overlap-save lag range: retain the last 256 complete chirps. */
    int first=FFT_N-LEN-CHIRP_PACKET+1,last=FFT_N-LEN;
    int64_t base=(int64_t)s->seen-FFT_N;
    for(int m=0;m<7;m++) {
        for(int j=0;j<FFT_N;j++)s->work[j]=(cx){s->raw[m][(base+j)&MASK]/8388608.f,0};
        fft(s,FFT_N,0);for(int k=0;k<FFT_N;k++)s->work[k]=mul(s->work[k],s->kernel[k]);
        fft(s,FFT_N,1);
        for(int j=first;j<=last;j++)s->h[m][(base+j)&MASK]=s->work[j];
    }
    if(s->h_first==INT64_MAX)s->h_first=base+first;
    if(s->h_end>=s->h_first+128) {
        float a[256];int count=0;
        for(int64_t i=s->h_end;i>=s->h_first&&count<256;i-=4)a[count++]=s->env[i&MASK];
        qsort(a,count,sizeof(float),cmpfloat);s->floor=fmaxf(a[count/2],1e-7f);
    }
    /* Fill the entire block before examining local peaks. */
    for(int j=first;j<=last;j++) {
        int64_t i=base+j;float e=0;for(int m=0;m<7;m++)e=fmaxf(e,mag(s->h[m][i&MASK]));s->env[i&MASK]=e;
    }
    s->h_end=base+last;
    for(int j=first;j<=last;j++) {
        int64_t i=base+j;
        if(i-s->h_first<256)continue; /* causal noise-floor warm-up */
        if(s->trigger<0&&i>s->dead_until&&s->env[i&MASK]>10*s->floor) {s->trigger=i;s->event_floor=s->floor;}
        if(s->trigger>=0&&i>=s->trigger+(int64_t)(.04*CHIRP_FS)) {
            if(start_event(s,i))s->dead_until=s->trigger+(int64_t)(.15*CHIRP_FS);
            s->trigger=-1;
        }
    }
    return 0;
}
static float power(chirp_state*s,float az,float el) {
    int g=(int)s->gate,n=s->nbin[g];float ux=cosf(az*PI/180)*cosf(el*PI/180),uy=sinf(az*PI/180)*cosf(el*PI/180);
    cx phase[7],step[7];
    for(int m=0;m<7;m++) {
        float d=(s->xy[m][0]*ux+s->xy[m][1]*uy)/343;
        float a=(float)(-2*PI*CHIRP_FS*UP/s->size[g])*d;
        step[m]=(cx){cosf(a),sinf(a)};phase[m]=(cx){cosf(a*s->firstbin[g]),sinf(a*s->firstbin[g])};
    }
    float total=0;
    for(int k=0;k<n;k++) {
        cx sum={0,0};
        for(int m=0;m<7;m++){cx v=mul(s->spec[g][m][k],phase[m]);sum.re+=v.re;sum.im+=v.im;phase[m]=mul(phase[m],step[m]);}
        total+=sum.re*sum.re+sum.im*sum.im;
    }
    return total/(n*49);
}
static float angular(float az,float el,float a2,float e2) {
    float dot=sinf(el*PI/180)*sinf(e2*PI/180)+cosf(el*PI/180)*cosf(e2*PI/180)*cosf((az-a2)*PI/180);
    return acosf(fminf(1,fmaxf(-1,dot)))*180/PI;
}
int chirp_service(chirp_state*s,unsigned budget) {
    if(!s||s->fatal)return 0;
    while(s->busy&&budget--) {
        float az,el;
        if(!s->refine){az=(float)(s->node%72)*5;el=(float)(s->node/72)*5;}
        else {az=s->refine_az+(int)(s->node%11)-5;el=s->refine_el+(int)(s->node/11)-5;}
        if(el>=0&&el<=90) {
            float p=power(s,az,el);
            if(p>s->best_power){s->best_power=p;s->best_az=az;s->best_el=el;}
        }
        s->node++;
        if(s->node<(s->refine?121U:1368U))continue;
        if(!s->refine){s->refine=1;s->node=0;s->refine_az=s->best_az;s->refine_el=s->best_el;continue;}
        s->az[s->gate]=fmodf(s->best_az+360,360);s->el[s->gate]=s->best_el;s->quality[s->gate]=s->best_power;
        if(++s->gate<3){s->node=0;s->refine=0;s->best_power=-1;continue;}
        s->result.azimuth_deg=s->az[0];s->result.elevation_deg=s->el[0];s->result.quality=s->quality[0];
        s->result.gate_difference_deg=fmaxf(angular(s->az[0],s->el[0],s->az[1],s->el[1]),angular(s->az[0],s->el[0],s->az[2],s->el[2]));
        unsigned status=s->el[0]>=85?CHIRP_ZENITH:CHIRP_OK;
        if(s->quality[0]<.85f)status=CHIRP_MODEL_MISMATCH;
        else if(s->quality[1]<.85f||s->quality[2]<.85f||s->result.gate_difference_deg>6)status=CHIRP_AMBIGUOUS;
        publish(s,status);
    }
    return s->busy!=0;
}
int chirp_take_result(chirp_state*s,chirp_result*out) {if(!s||!out||!s->ready)return 0;*out=s->result;s->ready=0;return 1;}
const char *chirp_status_name(uint32_t status) {
    static const char *names[]={"OK","ZENITH","MODEL_MISMATCH","AMBIGUOUS_ONSET","CLIPPED","CHANNEL_FAULT","OVERRUN","BAD_INPUT"};
    return status<sizeof(names)/sizeof(names[0])?names[status]:"UNKNOWN";
}
