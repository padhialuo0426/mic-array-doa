#ifndef MIC_CHIRP_H
#define MIC_CHIRP_H
#include <stddef.h>
#include <stdint.h>
#define CHIRP_FS (100000000.0/96.0/64.0)
#define CHIRP_PACKET 256
#define CHIRP_STORAGE_BYTES (640U*1024U)
typedef struct chirp_state chirp_state;
enum { CHIRP_OK, CHIRP_ZENITH, CHIRP_MODEL_MISMATCH, CHIRP_AMBIGUOUS,
       CHIRP_CLIPPED, CHIRP_CHANNEL_FAULT, CHIRP_OVERRUN, CHIRP_BAD_INPUT };
typedef struct {
    float azimuth_deg, elevation_deg, quality, gate_difference_deg;
    float level_dbfs, snr_db;
    uint32_t status, frame_sequence, latency_frames, azimuth_valid;
} chirp_result;
size_t chirp_state_size(void);
/* Storage must be 8-byte aligned. Mapping: physical M0..M6 -> raw channel. */
int chirp_init(chirp_state *s, const uint8_t mapping[7]);
/* Exactly 256 consecutive raw frames; corruption latches a fatal error. */
int chirp_feed(chirp_state *s, const uint32_t words[CHIRP_PACKET][8]);
/* Cooperative search: at most node_budget directions; returns work remaining. */
int chirp_service(chirp_state *s, unsigned node_budget);
int chirp_take_result(chirp_state *s, chirp_result *out);
const char *chirp_status_name(uint32_t status);
#endif
