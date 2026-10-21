// Swift -> C entry points of legacy/src/video_tvos.c (see legacy/src/tvos.h).
// Only what Swift calls; the nvp_* functions are defined in Swift (@_cdecl).
#ifndef NV_BRIDGE_H
#define NV_BRIDGE_H
#include "../../legacy/src/nativeui.h"
#include "../../legacy/src/swiftscene.h"
void nv_tvos_ev(int tipo, int a, int b);
void nv_tvos_faixa(int tipo, int id, const char *lingua, int flags, const char *nome,
                   const char *codec, int canais);
void nv_tvos_faixas_fim(int selAudio, int selLeg);
void nv_tvos_legenda(const char *texto, int durMs);
void nv_tvos_pos(int ms);
void nv_tvos_hdr(const char *hdr, int dv, int atmos);
void nv_tvos_retomada(int geracao, int aceita);
void nv_tvos_erro_texto(const char *texto);
// Legacy settings read by the player (ajustes.c).
int ajustes_player_apple_apac(void);
#endif
