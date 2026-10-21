#ifndef NV_REMOTE_TIMING_H
#define NV_REMOTE_TIMING_H
#include <stdint.h>

// Only a physically held direction repeats. A swipe never starts this clock.
typedef struct {
    int direction;
    uint32_t nextMove;
} NvRemoteTiming;

static inline void NvRemoteTimingReset(NvRemoteTiming *t) {
    *t = (NvRemoteTiming){0};
}

static inline int NvRemoteTimingPress(NvRemoteTiming *t, int direction, uint32_t now) {
    if (!direction || t->direction == direction) return 0;
    t->direction = direction;
    t->nextMove = now + 360;
    return 1;
}

static inline void NvRemoteTimingRelease(NvRemoteTiming *t, int direction) {
    if (t->direction == direction) NvRemoteTimingReset(t);
}

static inline int NvRemoteTimingRepeat(NvRemoteTiming *t, uint32_t now) {
    if (!t->direction || (int32_t)(now - t->nextMove) < 0) return 0;
    // Schedule from NOW, never catch up missed ticks after a busy frame.
    t->nextMove = now + 170;
    return t->direction;
}
#endif
