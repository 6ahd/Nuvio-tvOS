// Ponte entre o GLES2 da TV e o OpenGL do Mac.
//
// Existe para poder ver a UI no computador em vez de esperar o ciclo de
// empacotar, enviar e instalar na TV a cada ajuste de layout. O que roda no Mac
// e o MESMO codigo de desenho; muda so como as funcoes se chamam e o dialeto do
// shader. A TV continua sendo a palavra final — cor, escala e desempenho so
// valem medidos la.
#ifndef NV_GL_COMPAT_H
#define NV_GL_COMPAT_H

// NV_GLES_NO_MAC: o teste tests/fundo_assado.sh compila o nucleo no Mac
// contra o GLES2 do ANGLE (o dialeto e as regras de FBO da TV), nao o GL 2.1.
#if defined(NV_TVOS)
  // Apple TV: OpenGL ES 2 do sistema (OpenGLES.framework), mesmo dialeto da TV.
  #define GLES_SILENCE_DEPRECATION 1
  #include <OpenGLES/ES2/gl.h>
  #include <OpenGLES/ES2/glext.h>
  #define NV_GLSL_PREFIXO "precision mediump float;\n"
#elif defined(__APPLE__) && !defined(NV_GLES_NO_MAC)
  #define GL_SILENCE_DEPRECATION 1
  #include <OpenGL/gl.h>
  #include <OpenGL/glext.h>
  // Framebuffer de objeto e core no GLES2 e extensao no OpenGL 2.1 do Mac.
  #define glGenFramebuffers        glGenFramebuffersEXT
  #define glBindFramebuffer        glBindFramebufferEXT
  #define glFramebufferTexture2D   glFramebufferTexture2DEXT
  #define glCheckFramebufferStatus glCheckFramebufferStatusEXT
  #define glDeleteFramebuffers     glDeleteFramebuffersEXT
  #define glGenerateMipmap         glGenerateMipmapEXT
  #ifndef GL_FRAMEBUFFER
    #define GL_FRAMEBUFFER           GL_FRAMEBUFFER_EXT
  #endif
  #ifndef GL_COLOR_ATTACHMENT0
    #define GL_COLOR_ATTACHMENT0     GL_COLOR_ATTACHMENT0_EXT
  #endif
  #ifndef GL_FRAMEBUFFER_COMPLETE
    #define GL_FRAMEBUFFER_COMPLETE  GL_FRAMEBUFFER_COMPLETE_EXT
  #endif
  // GLSL 1.20 nao tem qualificadores de precisao; declara-los quebra a
  // compilacao, entao viram nada.
  #define NV_GLSL_PREFIXO \
    "#version 120\n" \
    "#define lowp\n#define mediump\n#define highp\n"
#else
  #include <GLES2/gl2.h>
  #define NV_GLSL_PREFIXO "precision mediump float;\n"
#endif

#include "perftv.h"
#ifdef NV_TVOS
#include "swiftscene.h"
#endif
// Count submitted pixel uploads (including text/mip levels), not allocations.
// Inline wrappers leave only a flag branch when measurement is off.
static inline void nvPerfTexImage2D(GLenum target, GLint level, GLint internal,
    GLsizei w, GLsizei h, GLint border, GLenum format, GLenum type, const void *pixels) {
  if (perftv_enabled && pixels) perftv_uploads++;
  glTexImage2D(target, level, internal, w, h, border, format, type, pixels);
#ifdef NV_TVOS
  if (nvscene_enabled() && target == GL_TEXTURE_2D && level == 0 && type == GL_UNSIGNED_BYTE) {
    GLint texture = 0, alignment = 4;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture); glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
    nvscene_texture((uint32_t)texture, level, 0, 0, w, h, format, alignment, pixels, 1);
  }
#endif
}
static inline void nvPerfTexSubImage2D(GLenum target, GLint level, GLint x, GLint y,
    GLsizei w, GLsizei h, GLenum format, GLenum type, const void *pixels) {
  if (perftv_enabled && pixels) perftv_uploads++;
  glTexSubImage2D(target, level, x, y, w, h, format, type, pixels);
#ifdef NV_TVOS
  if (nvscene_enabled() && target == GL_TEXTURE_2D && level == 0 && type == GL_UNSIGNED_BYTE) {
    GLint texture = 0, alignment = 4;
    glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture); glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment);
    nvscene_texture((uint32_t)texture, level, x, y, w, h, format, alignment, pixels, 0);
  }
#endif
}
#define glTexImage2D nvPerfTexImage2D
#define glTexSubImage2D nvPerfTexSubImage2D

#ifdef NV_TVOS
static inline void nvSceneDeleteTextures(GLsizei n, const GLuint *textures) {
  if (nvscene_enabled()) for (GLsizei i = 0; i < n; i++) nvscene_texture_delete(textures[i]);
  glDeleteTextures(n, textures);
}
static inline void nvSceneTexParameteri(GLenum target, GLenum property, GLint value) {
  glTexParameteri(target, property, value);
  if (nvscene_enabled() && target == GL_TEXTURE_2D && (property == GL_TEXTURE_MIN_FILTER || property == GL_TEXTURE_MAG_FILTER)) {
    GLint texture = 0; glGetIntegerv(GL_TEXTURE_BINDING_2D, &texture);
    nvscene_texture_filter((uint32_t)texture, (int)property, value);
  }
}
static inline void nvSceneBindFramebuffer(GLenum target, GLuint framebuffer) {
  if (nvscene_enabled() && target == GL_FRAMEBUFFER) nvscene_target_bind(framebuffer);
  glBindFramebuffer(target, framebuffer);
}
static inline void nvSceneFramebufferTexture2D(GLenum target, GLenum attachment,
    GLenum textarget, GLuint texture, GLint level) {
  glFramebufferTexture2D(target, attachment, textarget, texture, level);
  if (nvscene_enabled() && target == GL_FRAMEBUFFER && attachment == GL_COLOR_ATTACHMENT0) {
    GLint framebuffer = 0; glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
    nvscene_target_attach((uint32_t)framebuffer, texture);
  }
}
static inline void nvSceneDeleteFramebuffers(GLsizei n, const GLuint *framebuffers) {
  if (nvscene_enabled()) for (GLsizei i = 0; i < n; i++) nvscene_framebuffer_delete(framebuffers[i]);
  glDeleteFramebuffers(n, framebuffers);
}
static inline void nvSceneClear(GLbitfield mask) {
  if (nvscene_enabled() && (mask & GL_COLOR_BUFFER_BIT)) {
    GLfloat color[4]; GLint box[4], viewport[4];
    glGetFloatv(GL_COLOR_CLEAR_VALUE, color);
    glGetIntegerv(GL_SCISSOR_BOX, box); glGetIntegerv(GL_VIEWPORT, viewport);
    nvscene_clear(color[0], color[1], color[2], color[3], glIsEnabled(GL_SCISSOR_TEST),
                  box[0], box[1], box[2], box[3], viewport[2], viewport[3]);
    // Swift owns visible pixels; a transparent SDL backing canvas lets video
    // show through native scene holes without an old opaque GL frame.
    glClearColor(0, 0, 0, 0); glClear(mask); glClearColor(color[0], color[1], color[2], color[3]);
    return;
  }
  glClear(mask);
}
static inline void nvSceneReadPixels(GLint x, GLint y, GLsizei w, GLsizei h, GLenum format, GLenum type, void *bytes) {
  if (nvscene_enabled() && type == GL_UNSIGNED_BYTE && bytes) {
    GLint viewport[4], alignment = 4;
    glGetIntegerv(GL_VIEWPORT, viewport); glGetIntegerv(GL_PACK_ALIGNMENT, &alignment);
    if (nvscene_read_pixels(x, y, w, h, format, alignment, viewport[2], viewport[3], bytes)) return;
  }
  glReadPixels(x, y, w, h, format, type, bytes);
}
#define glDeleteTextures nvSceneDeleteTextures
#define glTexParameteri nvSceneTexParameteri
#define glBindFramebuffer nvSceneBindFramebuffer
#define glFramebufferTexture2D nvSceneFramebufferTexture2D
#define glDeleteFramebuffers nvSceneDeleteFramebuffers
#define glClear nvSceneClear
#define glReadPixels nvSceneReadPixels
#endif

#endif
