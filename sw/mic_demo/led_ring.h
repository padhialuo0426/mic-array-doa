#ifndef MIC_LED_RING_H
#define MIC_LED_RING_H
#include "chirp.h"
/* Fixed phone volume: fixed dBFS endpoints, never per-record AGC. */
#define LED_FAR_DBFS (-80.0f)
#define LED_NEAR_DBFS (-35.0f)
#define LED_STALE_FRAMES ((uint32_t)(CHIRP_FS*.75))
/* Logical D1->D12 clockwise. Physical chain offset and reversal are configurable
 * pending a later physical ring-index check. This does not alter mic mapping. */
typedef struct {int first_index, reversed; float far_dbfs, near_dbfs;} led_config;
int led_ring_render(const chirp_result *r, uint32_t age_frames,
                    const led_config *config, uint32_t pixels[12]);
#endif
