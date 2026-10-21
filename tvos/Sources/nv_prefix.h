// Forced into every C file of the tvOS build (OTHER_CFLAGS -include).
// tvOS forbids process spawning; the core only shells out for webOS/Mac-only
// paths (luna-send, open). Redirect those calls to a stub that fails cleanly.
#ifndef NV_TVOS_PREFIX_H
#define NV_TVOS_PREFIX_H
#if !defined(__OBJC__) && !defined(__cplusplus)
#include <stdlib.h>
#include <stdio.h>
int nv_tvos_system(const char *cmd);
FILE *nv_tvos_popen(const char *cmd, const char *mode);
int nv_tvos_pclose(FILE *f);
#define system nv_tvos_system
#define popen  nv_tvos_popen
#define pclose nv_tvos_pclose
#endif
#endif
