#include "amp_ipc.h"
#if defined(__arm__)
static void barrier(void){__asm__ volatile("dmb sy" ::: "memory");}
#else
#include <stdatomic.h>
static void barrier(void){atomic_thread_fence(memory_order_seq_cst);}
#endif
void amp_publish(volatile amp_shared*m,const chirp_result*r,uint64_t ms){
    m->result_seq++;barrier();m->result=*r;m->result_ms=ms;barrier();m->result_seq++;
}
int amp_snapshot(volatile amp_shared*m,chirp_result*r,uint64_t*ms,uint32_t*sequence){
    for(unsigned attempt=0;attempt<3;attempt++){
        uint32_t before=m->result_seq;if((before&1)||before==*sequence)return 0;
        barrier();chirp_result copy=m->result;uint64_t time=m->result_ms;barrier();
        if(before==m->result_seq){*r=copy;*ms=time;*sequence=before;return 1;}
    }
    return 0;
}
int amp_audio_push(volatile amp_shared*m,const uint32_t frames[CHIRP_PACKET][8]){
    uint32_t head=m->audio_head,tail=m->audio_tail;barrier();
    if(head-tail>=AMP_SLOTS){m->audio_drops++;return 0;}
    for(unsigned i=0;i<CHIRP_PACKET;i++)m->audio[head&(AMP_SLOTS-1)][i]=(int32_t)frames[i][6];
    barrier();m->audio_head=head+1;return 1;
}
int amp_audio_pop(volatile amp_shared*m,int32_t mono[CHIRP_PACKET]){
    uint32_t tail=m->audio_tail,head=m->audio_head;if(head==tail)return 0;barrier();
    for(unsigned i=0;i<CHIRP_PACKET;i++)mono[i]=m->audio[tail&(AMP_SLOTS-1)][i];
    barrier();m->audio_tail=tail+1;return 1;
}
