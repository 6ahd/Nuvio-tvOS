// Use host GL declarations only; this test exercises C track state, no drawing.
#include "../../legacy/src/gl_compat.h"
#define NV_TVOS 1
#include "../../legacy/src/video_tvos.c"
#include <assert.h>

const char *ling_audio(void) { return ""; }
int ling_casa(const char *code, const char *pref) { return !strcmp(code, pref); }
const char *ling_nome(const char *code) { return code; }
void nvp_escolher(int kind, int value) { (void)kind; (void)value; }
int SDL_LockMutex(SDL_mutex *m) { (void)m; return 0; }
int SDL_UnlockMutex(SDL_mutex *m) { (void)m; return 0; }

int main(void) {
    // First report installs subtitles and no selection.
    nNovasA = 2; nNovasL = 2;
    novasL[0].numero = 40; novasL[1].numero = 41;
    nv_tvos_faixas_fim(0, -1);
    assert(nAudio == 2 && nLeg == 2 && legAtual == -1);
    video_escolher_legenda(1);
    assert(legAtual == 1);
    // The Swift bridge now sends audio only when Atmos metadata changes.
    nNovasA = 2; nNovasL = 0;
    nv_tvos_faixas_fim(1, -1);
    assert(legAtual == 1 && faixaLeg[1].numero == 41 && audioAtual == 1);
    puts("video tracks: PASS (audio refresh preserves selected subtitle)");
}
