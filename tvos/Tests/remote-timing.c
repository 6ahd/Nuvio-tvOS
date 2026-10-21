#include "../Sources/NvRemoteTiming.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    NvRemoteTiming t = {0};
    // All four directions start immediately and release independently.
    for (int direction = 1; direction <= 4; direction++) {
        assert(NvRemoteTimingPress(&t, direction, 1000));
        assert(!NvRemoteTimingPress(&t, direction, 1001));
        assert(!NvRemoteTimingRepeat(&t, 1359));
        assert(NvRemoteTimingRepeat(&t, 1360) == direction);
        assert(!NvRemoteTimingRepeat(&t, 1529));
        assert(NvRemoteTimingRepeat(&t, 1530) == direction);
        NvRemoteTimingRelease(&t, direction);
        assert(!NvRemoteTimingRepeat(&t, 9000));
    }
    // Separate quick clicks are never treated as a held button.
    assert(NvRemoteTimingPress(&t, 1, 10000));
    NvRemoteTimingRelease(&t, 1);
    assert(NvRemoteTimingPress(&t, 1, 10001));
    // Reversal is immediate; releasing the old direction leaves the new one held.
    assert(NvRemoteTimingPress(&t, 2, 10002));
    NvRemoteTimingRelease(&t, 1);
    assert(t.direction == 2);
    // A busy frame gets one repeat, never a backlog of missed timer ticks.
    assert(NvRemoteTimingRepeat(&t, 20000) == 2);
    for (unsigned i = 0; i < 100; i++) assert(!NvRemoteTimingRepeat(&t, 20000));
    NvRemoteTimingReset(&t); // focus loss / keyboard / background
    assert(!NvRemoteTimingRepeat(&t, 21000));
    // A swipe never starts a repeat timer.
    for (uint32_t ms = 0; ms < 10000; ms += 10) assert(!NvRemoteTimingRepeat(&t, ms));
    // SDL's 32-bit clock wraps after long uptime.
    assert(NvRemoteTimingPress(&t, 4, UINT32_MAX - 100));
    assert(!NvRemoteTimingRepeat(&t, 258));
    assert(NvRemoteTimingRepeat(&t, 259) == 4);
    puts("remote timing: PASS (four directions, quick clicks, holds, reversal, stalls, release, clock wrap)");
}
