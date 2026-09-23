#include "led_ring.h"
#include <math.h>
#include <string.h>
static int index_of(int logical,const led_config*c) {return (c->first_index+(c->reversed?-logical:logical)+24)%12;}
int led_ring_render(const chirp_result*r,uint32_t age,const led_config*c,uint32_t pixels[12]) {
    if(!pixels)return -1;
    memset(pixels,0,12*sizeof(uint32_t));
    if(!r||!c||c->first_index<0||c->first_index>=12||(c->reversed!=0&&c->reversed!=1)||
       !isfinite(c->far_dbfs)||!isfinite(c->near_dbfs)||c->near_dbfs<=c->far_dbfs)return -1;
    if(age>LED_STALE_FRAMES||!isfinite(r->level_dbfs)||!isfinite(r->elevation_deg)||
       r->elevation_deg<0||r->elevation_deg>90)return 0;
    float v=(r->level_dbfs-c->far_dbfs)/(c->near_dbfs-c->far_dbfs);
    v=fminf(1,fmaxf(0,v));int brightness=(int)lroundf(v*255);
    if(!brightness)return 0;
    if(r->status==CHIRP_ZENITH) {
        /* Two opposite blue lamps mean near-zenith: no meaningful azimuth. */
        pixels[index_of(0,c)]=pixels[index_of(6,c)]=(4U<<24)|((uint32_t)brightness<<16);
        return 0;
    }
    if(r->status!=CHIRP_OK||!r->azimuth_valid||!isfinite(r->azimuth_deg))return 0;
    float q=fmodf(-r->azimuth_deg,360);if(q<0)q+=360;q/=30;
    int a=(int)floorf(q),b=(a+1)%12;float fraction=q-a;
    unsigned va=(unsigned)lroundf(brightness*(1-fraction)),vb=(unsigned)lroundf(brightness*fraction);
    if(va)pixels[index_of(a,c)]=(4U<<24)|(va<<8);
    if(vb)pixels[index_of(b,c)]=(4U<<24)|(vb<<8);
    return 0;
}
