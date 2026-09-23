#include "doa.h"
#include <math.h>
#include <string.h>
#define PI 3.14159265358979323846
#define DEG (PI/180.0)
#define MIN_DBFS (-80.0)
#define MIN_COHERENCE .65
#define MIN_FIT .80
#define ZENITH_DEG 85.0

static double norm2(doa_complex a) { return a.re*a.re+a.im*a.im; }
static doa_complex product(doa_complex a,doa_complex b) {
    doa_complex v={a.re*b.re-a.im*b.im,a.re*b.im+a.im*b.re}; return v;
}
static doa_complex cross(doa_complex a,doa_complex b) {
    doa_complex v={a.re*b.re+a.im*b.im,a.im*b.re-a.re*b.im}; return v;
}
static double wrap(double a) { a=fmod(a,360.0);return a<0?a+360:a; }
static double bounded(double a) {return a<0?0:(a>90?90:a);}
static void steering(double frequency,double az,double el,doa_complex a[7]) {
    double k=2*PI*frequency/343.0*.04*cos(el*DEG);
    for(unsigned m=0;m<6;m++) {
        double phase=k*cos((az+60*m)*DEG);
        a[m].re=cos(phase);a[m].im=sin(phase);
    }
    a[6].re=1;a[6].im=0;
}
size_t doa_state_size(void) {return sizeof(doa_state);}
int doa_init(doa_state *s,double frequency,uint32_t settle_frames) {
    if(!s || !isfinite(frequency) || frequency<500 || frequency>4000)return -1;
    memset(s,0,sizeof(*s));s->frequency=frequency;s->skip=settle_frames;
    double sum=0;
    for(unsigned n=0;n<DOA_WINDOW;n++) {
        double w=.5-.5*cos(2*PI*n/(DOA_WINDOW-1));
        double phase=-2*PI*frequency*n/DOA_FS;
        s->kernel[n].re=w*cos(phase);s->kernel[n].im=w*sin(phase);
        s->kernel_sum_re+=s->kernel[n].re;s->kernel_sum_im+=s->kernel[n].im;sum+=w;
    }
    s->normalization=2.0/(sum*8388608.0);
    for(unsigned i=0;i<7;i++)s->mapping[i]=(uint8_t)i;
    unsigned index=0;
    for(unsigned el=0;el<=90;el+=15)for(unsigned az=0;az<360;az+=15)
        steering(frequency,az,el,s->coarse[index++]);
    return 0;
}
int doa_set_mapping(doa_state *s,const uint8_t mapping[7]) {
    unsigned bits=0;
    if(!s || !mapping || s->have_sequence)return -1;
    for(unsigned i=0;i<7;i++) {
        if(mapping[i]>=7 || (bits&(1U<<mapping[i])))return -1;
        bits|=1U<<mapping[i];
    }
    memcpy(s->mapping,mapping,7);return 0;
}
static void matvec(const doa_complex r[7][7],const doa_complex u[7],doa_complex v[7]) {
    for(unsigned i=0;i<7;i++) {
        v[i].re=0;v[i].im=0;
        for(unsigned j=0;j<7;j++) {
            doa_complex t=product(r[i][j],u[j]);v[i].re+=t.re;v[i].im+=t.im;
        }
    }
}
static double dominant(const doa_complex r[7][7],double trace,doa_complex best[7],double *residual) {
    double best_lambda=-1,best_residual=1;
    /* Two deterministic dense starts avoid a channel-local starting vector
       getting trapped in a weaker, spatially isolated eigenmode. Low-eigengap
       cases are rejected by coherence/residual gates, never forced to an angle. */
    for(unsigned seed=0;seed<2;seed++) {
        doa_complex u[7],v[7];
        for(unsigned i=0;i<7;i++) {double p=seed*.73*i;u[i].re=cos(p)/sqrt(7.0);u[i].im=sin(p)/sqrt(7.0);}
        for(unsigned iter=0;iter<96;iter++) {
            matvec(r,u,v);double size=0;
            for(unsigned i=0;i<7;i++)size+=norm2(v[i]);
            size=sqrt(size);if(size<1e-30)break;
            for(unsigned i=0;i<7;i++){u[i].re=v[i].re/size;u[i].im=v[i].im/size;}
            matvec(r,u,v);double lambda=0,error=0;
            for(unsigned i=0;i<7;i++)lambda+=u[i].re*v[i].re+u[i].im*v[i].im;
            for(unsigned i=0;i<7;i++) {doa_complex e={v[i].re-lambda*u[i].re,v[i].im-lambda*u[i].im};error+=norm2(e);}
            error=sqrt(error)/trace;
            if(iter==95 || error<1e-10) {
                if(lambda>best_lambda) {best_lambda=lambda;best_residual=error;memcpy(best,u,sizeof(u));}
                break;
            }
        }
    }
    *residual=best_residual;return best_lambda;
}
static double score(const doa_complex u[7],const doa_complex a[7]) {
    doa_complex sum={0,0};
    for(unsigned i=0;i<7;i++){doa_complex t=cross(a[i],u[i]);sum.re+=t.re;sum.im+=t.im;}
    return norm2(sum);
}
int doa_solve(doa_state *s,const doa_complex r[7][7],doa_result *o) {
    if(!s || !o || !r)return -1;
    memset(o,0,sizeof(*o));o->azimuth_deg=NAN;o->elevation_deg=NAN;
    o->tone_dbfs=-300;o->status=DOA_BAD_INPUT;
    double trace=0;
    for(unsigned i=0;i<7;i++)for(unsigned j=0;j<7;j++)
        if(!isfinite(r[i][j].re) || !isfinite(r[i][j].im))return -1;
    for(unsigned i=0;i<7;i++){if(r[i][i].re<0)return -1;trace+=r[i][i].re;}
    for(unsigned i=0;i<7;i++)for(unsigned j=0;j<7;j++)
        if(fabs(r[i][j].re-r[j][i].re)>trace*1e-10 || fabs(r[i][j].im+r[j][i].im)>trace*1e-10)return -1;
    o->tone_dbfs=10*log10(fmax(trace/7,1e-30));
    if(o->tone_dbfs<MIN_DBFS){o->status=DOA_LOW_SIGNAL;return 0;}
    doa_complex u[7];double lambda=dominant(r,trace,u,&o->residual);
    o->coherence=lambda/trace;
    if(o->coherence<MIN_COHERENCE){o->status=DOA_INCOHERENT;return 0;}
    if(o->residual>1e-7){o->status=DOA_EIGEN_FAIL;return 0;}
    double az=0,el=0,best=-1;
    for(unsigned i=0;i<DOA_COARSE;i++) {
        double value=score(u,s->coarse[i]);
        if(value>best){best=value;az=(i%24)*15;el=(i/24)*15;}
    }
    if(el==90) {
        /* All azimuths coincide at the pole. Seed its tangent direction from
           a nearby latitude instead of arbitrarily refining from azimuth 0. */
        double ring_best=-1;
        for(unsigned a=0;a<360;a+=15) {
            doa_complex v[7];steering(s->frequency,a,85,v);
            double value=score(u,v);
            if(value>ring_best){ring_best=value;az=a;}
        }
    }
    /* Bounded 2-D pattern refinement. Compare with full noise-subspace dense
       grids in Python; this search contains no truth-angle information. */
    for(double step=7.5;step>=.02;step*=.5) {
        for(unsigned iteration=0;iteration<12;iteration++) {
            double next_az=az,next_el=el,next_score=best;
            for(int da=-1;da<=1;da++)for(int de=-1;de<=1;de++) {
                if(!da && !de)continue;
                double a=wrap(az+da*step),e=bounded(el+de*step);
                doa_complex steering_vector[7];steering(s->frequency,a,e,steering_vector);
                double value=score(u,steering_vector);
                if(value>next_score+1e-14){next_score=value;next_az=a;next_el=e;}
            }
            if(next_score<=best+1e-14)break;
            best=next_score;az=next_az;el=next_el;
        }
    }
    o->fit=fmin(1,fmax(0,best/7));
    if(o->fit<MIN_FIT){o->status=DOA_MODEL_MISMATCH;return 0;}
    o->azimuth_deg=wrap(az);o->elevation_deg=el;o->azimuth_valid=el<ZENITH_DEG;
    o->status=o->azimuth_valid?DOA_OK:DOA_ZENITH;return 0;
}
int doa_feed(doa_state *s,const uint32_t frame[8],doa_result *o) {
    if(!s || !frame || !o)return -1;
    for(unsigned ch=0;ch<7;ch++)if(frame[ch]&255U)return -1;
    if(s->have_sequence && frame[7]!=s->previous_sequence+1U)return -1;
    s->previous_sequence=frame[7];s->have_sequence=1;
    if(s->skip){s->skip--;return 0;}
    unsigned pos=s->write_pos,clipped=0;
    s->clipped_count-=s->clip_ring[pos];
    for(unsigned ch=0;ch<7;ch++) {
        uint32_t v=frame[s->mapping[ch]]>>8;
        int32_t sample=(int32_t)v-((v&0x800000U)?0x1000000:0);
        s->ring[pos][ch]=sample;
        clipped|=sample>=8380000 || sample<=-8380000;
    }
    s->clip_ring[pos]=(uint8_t)clipped;s->clipped_count+=clipped;
    s->write_pos=(pos+1)%DOA_WINDOW;
    if(s->filled<DOA_WINDOW) {
        s->filled++;if(s->filled<DOA_WINDOW)return 0;
    } else {s->hop_count++;if(s->hop_count<DOA_HOP)return 0;s->hop_count=0;}
    unsigned slot=s->snapshot_count%DOA_HISTORY;
    for(unsigned ch=0;ch<7;ch++) {
        double sum=0,re=0,im=0;
        for(unsigned n=0;n<DOA_WINDOW;n++) {
            double x=s->ring[(s->write_pos+n)%DOA_WINDOW][ch];
            sum+=x;re+=x*s->kernel[n].re;im+=x*s->kernel[n].im;
        }
        double mean=sum/DOA_WINDOW;
        s->history[slot][ch].re=(re-mean*s->kernel_sum_re)*s->normalization;
        s->history[slot][ch].im=(im-mean*s->kernel_sum_im)*s->normalization;
    }
    s->clip_history[slot]=s->clipped_count!=0;s->snapshot_count++;
    if(s->snapshot_count<DOA_HISTORY || s->snapshot_count%3)return 0;
    doa_complex covariance[7][7]={0};
    for(unsigned k=0;k<DOA_HISTORY;k++)for(unsigned i=0;i<7;i++)for(unsigned j=0;j<7;j++) {
        doa_complex t=cross(s->history[k][i],s->history[k][j]);
        covariance[i][j].re+=t.re/DOA_HISTORY;covariance[i][j].im+=t.im/DOA_HISTORY;
    }
    if(doa_solve(s,covariance,o))return -1;
    for(unsigned k=0;k<DOA_HISTORY;k++)if(s->clip_history[k]) {
        o->status=DOA_CLIPPED;o->azimuth_valid=0;o->azimuth_deg=NAN;o->elevation_deg=NAN;
    }
    o->snapshots=s->snapshot_count;o->frame_sequence=frame[7];return 1;
}
const char *doa_status_name(uint32_t status) {
    static const char *names[]={"OK","ZENITH","LOW_SIGNAL","INCOHERENT","MODEL_MISMATCH","EIGEN_FAIL","NOT_READY","CLIPPED","BAD_INPUT"};
    return status<sizeof(names)/sizeof(names[0])?names[status]:"BAD_INPUT";
}
