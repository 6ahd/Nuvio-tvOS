// tvOS presentation adapter. The C core remains the source of truth for layout,
// account/catalogue state and actions; Swift supplies native focusable controls.
#ifndef NV_NATIVE_UI_H
#define NV_NATIVE_UI_H
#include <stdint.h>

typedef struct {
  uint64_t identity;
  float x, y, w, h;
  uint32_t flags; // 1 = custom activation on Select release (no SDL OK).
} NvUIControl;

// Also imported by the standalone UIKit integration test host.
void nvui_key(int key, int down);
int nvui_focus(uint64_t identity);
int nvui_activate(uint64_t identity);

void nvui_controls(const NvUIControl *controls, int count, uint64_t preferred);
void nvui_frame_begin(int home, int enabled);
void nvui_frame_end(void);
// Keys: 0 up, 1 down, 2 left, 3 right, 4 select, 5 menu, 6 play/pause.
void *nvui_focus_environment(void);
int nvui_owns_focus(void);
int nvui_poster(uint64_t identity, const char *url, float x, float y, float w,
                float h, float radius, float clipTop, int cover, float focus);
void nvui_image_rgba(const char *url, const void *rgba, int w, int h, int pitch);
void nvui_label(uint64_t identity, const char *label);
#endif
