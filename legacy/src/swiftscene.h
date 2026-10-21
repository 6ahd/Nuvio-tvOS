// Presentation-only bridge. Catalogue, playback and account state stay in the
// shared core; tvOS presents its complete scene using Swift/UIKit.
#ifndef NV_SWIFT_SCENE_H
#define NV_SWIFT_SCENE_H
#include <stdint.h>

typedef struct { float x, y, w, h; } NvSceneRect;
typedef struct { float r, g, b, a; } NvSceneColor;
typedef struct {
  int32_t mode;
  uint32_t texture, texture2, flags;
  NvSceneRect rect, clip, uv;
  NvSceneColor color, background, grad0, grad1, grad2;
  NvSceneColor ambient0, ambient1, ambient2, ambient3, veil;
  float focus, parx, pary, radius, aspect, aspect2, alpha2;
  float rotation, centerX, centerY, slide, border, reflect, sweep;
  float bottom0, bottomAlpha0, bottom1, bottomAlpha1;
  float time;
} NvSceneCommand;

// flags: 1 clip, 2 forced cover, 4 screen-edge veil, 8 opaque RGB,
// 16 gradient accent, 32 replacement blend (video hole), 64 secondary image.
#ifdef NV_TVOS
int nvscene_enabled(void);
void nvscene_wait_frame(void);
void nvscene_begin(const char *screen, float r, float g, float b);
void nvscene_draw(const NvSceneCommand *command);
void nvscene_end(void);
void nvscene_dissolve(float alpha);
void nvscene_target_begin(uint32_t texture, int w, int h,
                          float x, float y, float scale, int clear);
void nvscene_target_end(void);
void nvscene_alias(uint32_t texture, uint32_t source, float blur);
void nvscene_text(uint32_t texture, const char *text, const char *family,
                  const char *face, float size, float ascent, float lineHeight, float tracking,
                  float r, float g, float b, float a, int emphasis);
void nvscene_texture(uint32_t texture, int level, int x, int y, int w, int h,
                     int format, int alignment, const void *bytes, int replace);
void nvscene_texture_delete(uint32_t texture);
void nvscene_texture_filter(uint32_t texture, int property, int value);
void nvscene_target_bind(uint32_t framebuffer);
void nvscene_target_attach(uint32_t framebuffer, uint32_t texture);
void nvscene_framebuffer_delete(uint32_t framebuffer);
void nvscene_clear(float r, float g, float b, float a, int clipped,
                   int x, int y, int w, int h, int viewportW, int viewportH);
int nvscene_read_pixels(int x, int y, int w, int h, int format, int alignment,
                        int viewportW, int viewportH, void *bytes);
#endif
#endif
