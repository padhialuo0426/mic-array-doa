#ifndef MIC_DOA_H
#define MIC_DOA_H
#include <stddef.h>
#include <stdint.h>
#define DOA_CHANNELS 7
#define DOA_WINDOW 1024
#define DOA_HOP 512
#define DOA_HISTORY 8
#define DOA_SETTLE_FRAMES 16384U
#define DOA_FS (100000000.0/96.0/64.0)
#define DOA_COARSE 168
typedef struct { double re, im; } doa_complex;
enum { DOA_OK, DOA_ZENITH, DOA_LOW_SIGNAL, DOA_INCOHERENT,
       DOA_MODEL_MISMATCH, DOA_EIGEN_FAIL, DOA_NOT_READY, DOA_CLIPPED, DOA_BAD_INPUT };
typedef struct {
    double azimuth_deg, elevation_deg, tone_dbfs, coherence, fit, residual;
    uint32_t status, snapshots, frame_sequence, azimuth_valid;
} doa_result;
typedef struct {
    double frequency, kernel_sum_re, kernel_sum_im, normalization;
    doa_complex kernel[DOA_WINDOW];
    doa_complex coarse[DOA_COARSE][DOA_CHANNELS];
    int32_t ring[DOA_WINDOW][DOA_CHANNELS];
    uint8_t clip_ring[DOA_WINDOW], mapping[DOA_CHANNELS], clip_history[DOA_HISTORY];
    doa_complex history[DOA_HISTORY][DOA_CHANNELS];
    uint32_t write_pos, filled, hop_count, snapshot_count, skip, previous_sequence;
    uint32_t have_sequence, clipped_count;
} doa_state;
size_t doa_state_size(void);
int doa_init(doa_state *state, double frequency, uint32_t settle_frames);
int doa_set_mapping(doa_state *state, const uint8_t mapping[DOA_CHANNELS]);
int doa_solve(doa_state *state, const doa_complex covariance[DOA_CHANNELS][DOA_CHANNELS], doa_result *result);
/* Return 1 for a result, 0 while filling, -1 for format/sequence corruption. */
int doa_feed(doa_state *state, const uint32_t frame[8], doa_result *result);
const char *doa_status_name(uint32_t status);
#endif
