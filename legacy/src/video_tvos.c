// Player da Apple TV. Quem toca e o AetherEngine do NuvioTVOS (NvPlayer.swift),
// numa AetherPlayerView ATRAS da view GL do SDL (furo, como no Android). Aqui
// fica so o estado que o resto do app le (video.h) e as chamadas ao Swift.
// Desenho copiado do video_android.c: o Swift avisa pelos nv_tvos_* e o app le
// o estado no quadro dele. No tvOS o SDL e o Swift dividem o fio principal,
// entao nada aqui corre em paralelo; os volatile ficam por simetria.
//
// DIFERENCAS EM RELACAO AO ANDROID
//  * Sem PCM (F06) e sem cache/reforco de volume (F07): cacheboost.c segue com
//    os cotos de sempre e a linha do ajuste diz "indisponivel".
//  * Legenda embutida de texto: o Swift entrega o cue em vigor
//    (nv_tvos_legenda) e o app desenha, igual ao Media3. Bitmap (PGS) ainda nao.
//  * Retomada: so segundos exatos vao na abertura (startPosition do motor). O
//    percentual cai no seek depois do pronto, como no Android sem
//    abrirRetomada.
#ifdef NV_TVOS
#include "marco.h"
#include "streams.h"
#include "video.h"
#include "capmkv.h"
#include "audioinfo.h"
#include "video_reconexao.h"
#include "idioma.h"
#include "linguas.h"
#include "velocidade.h"
#include "tvos.h"
#include "addons.h"
#include "ajustes.h"
#include <SDL2/SDL.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <strings.h>

// --- estado ------------------------------------------------------------------
#define MAX_FAIXAS NV_FAIXA_MAX
static VideoFaixa faixaAudio[MAX_FAIXAS], faixaLeg[MAX_FAIXAS];
static volatile int nAudio, nLeg, audioAtual, legAtual = -1;
static SDL_mutex *travaLeg;
static char legTexto[1024];
static Uint32 legAte;

static char urlAtual[4096];
static char cabecalhos[2048];
static int envX, envY, envW, envH, envEnc, temEnv;
static volatile int superficieEstavel;
static volatile int ativo, prontoLoad, primeiroQuadro, falhou, terminou, tocando, largura, altura;
static volatile int semDecoderAudio;
static volatile int pausaPedida, pausaVista;
static volatile int durMs, bufferando, posMs;
static volatile int velPedida = 100, velEnviada = 100, velRecusada;
static volatile Uint32 bufferDesde, tocandoDesde;
static volatile const char *hdrAtual = "none";
static volatile int dvAtual, atmosAtual;
static unsigned sessao;
static int retomadaInicialEstado = -1;
static pthread_mutex_t travaRetomada = PTHREAD_MUTEX_INITIALIZER;
#define TVOS_FURO_PRAZO_MS 3000u   // sem quadro (so audio): abre 3 s depois de tocar

static NvReconexao recon;
static int reconProxima, reconPermitida, reconIniciou;
static volatile int reconErroPend, reconErroCod, reconErroVideo;
static int reconAudio = -1, reconLeg = -1;
static volatile int reconFaixasPend;
static int reconBuscarMs = -1;
static char erroTxt[64];

// Erros de rede do NvPlayer.swift (codigo 2000..2002, mesmo intervalo do
// Media3, para o video_bombear decidir igual ao Android).
static int erroDeRede(int cod) { return cod >= 2000 && cod <= 2002; }

void video_escolher_audio(int i);

static void escolherAudioPreferido(void) {
  const char *pref = ling_audio();
  int i;
  if (!pref[0] || nAudio < 2) return;
  if (audioAtual >= 0 && audioAtual < nAudio && faixaAudio[audioAtual].idioma[0] &&
      ling_casa(faixaAudio[audioAtual].idioma, pref)) return;
  for (i = 0; i < nAudio; i++) {
    if (!faixaAudio[i].idioma[0] || !ling_casa(faixaAudio[i].idioma, pref)) continue;
    printf("[video] audio preferido: %s (faixa %d de %d)\n", ling_nome(faixaAudio[i].idioma), i + 1, nAudio);
    video_escolher_audio(i);
    return;
  }
}

// --- Swift -> C --------------------------------------------------------------
static VideoFaixa novasA[MAX_FAIXAS], novasL[MAX_FAIXAS];
static int nNovasA, nNovasL;

// `flags`: bit 0 = forcada, bit 1 = SDH. `codec`: nome do FFmpeg ("eac3") ou
// "audio/eac3-joc" para Atmos (audioinfo.c conhece os dois).
void nv_tvos_faixa(int tipo, int id, const char *lingua, int flags, const char *nome,
                   const char *codec, int canais) {
  VideoFaixa *f;
  char l[16], nm[48], ai[40];
  snprintf(l, sizeof l, "%s", lingua ? lingua : "");
  snprintf(nm, sizeof nm, "%s", nome ? nome : "");
  if (tipo == 0) { if (nNovasA >= MAX_FAIXAS) return; f = &novasA[nNovasA++]; }
  else           { if (nNovasL >= MAX_FAIXAS) return; f = &novasL[nNovasL++]; }
  memset(f, 0, sizeof *f);
  f->numero = id;
  f->ordinalMkv = tipo ? nNovasL - 1 : -1;
  if (l[0] && strcmp(l, "und") && strcmp(l, "unknown") && strcmp(l, "zxx"))
    snprintf(f->idioma, sizeof f->idioma, "%s", l);
  if (f->idioma[0]) snprintf(f->rotulo, sizeof f->rotulo, "%s", i18n(ling_nome(f->idioma)));
  else if (nm[0]) snprintf(f->rotulo, sizeof f->rotulo, "%s", nm);
  else snprintf(f->rotulo, sizeof f->rotulo, "%s %d", i18n(tipo ? "Legenda" : "Áudio"),
                tipo ? nNovasL : nNovasA);
  if (tipo) {
    const char *r;
    snprintf(f->codec, sizeof f->codec, "%s", codec ? codec : "");
    f->tipoLeg = ling_tipo_legenda(nm, flags & 1, (flags & 2) != 0);
    f->letreiro = f->tipoLeg == LING_LEG_FORCADA || f->tipoLeg == LING_LEG_LETREIROS;
    r = ling_tipo_legenda_rotulo(f->tipoLeg);
    if (r) {
      size_t k = strlen(f->rotulo);
      snprintf(f->rotulo + k, sizeof f->rotulo - k, "  \xc2\xb7  %s", i18n(r));
    }
  } else {
    snprintf(f->codec, sizeof f->codec, "%s", codec ? codec : "");
    f->canais = canais;
    if (audioinfo_texto(f->codec, canais, 0, ai, sizeof ai))
    { char base[sizeof f->rotulo];
      snprintf(base, sizeof base, "%s", f->rotulo);
      snprintf(f->rotulo, sizeof f->rotulo, "%s  \xc2\xb7  %s", base, ai); }
  }
}

void nv_tvos_faixas_fim(int selAudio, int selLeg) {
  int releitura = (nAudio || nLeg) && !nNovasL && nLeg;
  (void)selLeg;
  memcpy(faixaAudio, novasA, sizeof novasA);
  audioAtual = selAudio >= 0 ? selAudio : 0;
  if (!releitura) {
    memcpy(faixaLeg, novasL, sizeof novasL);
    legAtual = -1;
    nLeg = nNovasL;
  }
  nAudio = nNovasA;
  nNovasA = nNovasL = 0;
  printf("[video] faixas: %d audio, %d legenda\n", nAudio, nLeg);
  fflush(stdout);
  if (reconFaixasPend) {
    if (!releitura && reconLeg >= 0 && reconLeg < nLeg) video_escolher_legenda(reconLeg);
    if (nAudio > 0) {
      reconFaixasPend = 0;
      if (reconAudio > 0 && reconAudio < nAudio) video_escolher_audio(reconAudio);
    }
    printf("[video] reconexao: faixas devolvidas (audio %d, legenda %d)\n", reconAudio, reconLeg);
    fflush(stdout);
    return;
  }
  escolherAudioPreferido();
}

void nv_tvos_legenda(const char *texto, int dur) {
  if (!travaLeg) return;
  SDL_LockMutex(travaLeg);
  snprintf(legTexto, sizeof legTexto, "%s", texto ? texto : "");
  legAte = SDL_GetTicks() + (Uint32)(dur > 0 ? dur : 3000);
  SDL_UnlockMutex(travaLeg);
}

void nv_tvos_pos(int ms) { posMs = ms; }

void video_estatisticas(VideoStats *s) { video_stats_vazio(s); }

void nv_tvos_retomada(int geracao, int aceita) {
  pthread_mutex_lock(&travaRetomada);
  if ((unsigned)geracao == sessao) retomadaInicialEstado = aceita ? 1 : -1;
  pthread_mutex_unlock(&travaRetomada);
}
int video_retomada_inicial_estado(void) {
  int estado;
  pthread_mutex_lock(&travaRetomada);
  estado = retomadaInicialEstado;
  pthread_mutex_unlock(&travaRetomada);
  return estado;
}
static unsigned novaRetomada(int estado) {
  unsigned geracao;
  pthread_mutex_lock(&travaRetomada);
  if (++sessao == 0) sessao++;
  geracao = sessao; retomadaInicialEstado = estado;
  pthread_mutex_unlock(&travaRetomada);
  return geracao;
}
static void estadoRetomada(int estado) {
  pthread_mutex_lock(&travaRetomada);
  retomadaInicialEstado = estado;
  pthread_mutex_unlock(&travaRetomada);
}

void nv_tvos_erro_texto(const char *t) {
  printf("[video] tvos erro: %s\n", t ? t : "");
  fflush(stdout);
}

void nv_tvos_hdr(const char *h, int dv, int atmos) {
  h = h ? h : "";
  hdrAtual = !strcmp(h, "HDR10") ? "HDR10" : !strcmp(h, "HLG") ? "HLG" :
             !strcmp(h, "DolbyVision") ? "DolbyVision" : "none";
  dvAtual = dv != 0;
  atmosAtual = atmos != 0;
  printf("[video] tvos hdr=%s dv=%d atmos=%d\n", (const char *)hdrAtual, dvAtual, atmosAtual);
  fflush(stdout);
}

enum { EV_PRONTO = 1, EV_TOCANDO = 2, EV_PAUSADO = 3, EV_FIM = 4, EV_ERRO = 5,
       EV_TAMANHO = 6, EV_BUFFER = 7, EV_PRIMEIRO_QUADRO = 8, EV_AUDIO_SEM_DECODER = 9,
       EV_SUPERFICIE_ESTAVEL = 10 };

void nv_tvos_ev(int tipo, int a, int b) {
  switch (tipo) {
    case EV_PRONTO:  if (!prontoLoad) marco("video: pronto (tvos)"); durMs = a; prontoLoad = 1; break;
    case EV_TOCANDO: tocando = 1; bufferando = 0; pausaVista = 0; if (!tocandoDesde) tocandoDesde = SDL_GetTicks() | 1; break;
    case EV_PAUSADO: tocando = 0; if (pausaPedida) pausaVista = 1; break;
    case EV_FIM:     terminou = 1; tocando = 0; break;
    case EV_ERRO:    reconErroCod = a; reconErroVideo = b == 2;
                     reconErroPend = 1; tocando = 0;
                     snprintf(erroTxt, sizeof erroTxt, "%d player error:%d", a, b);
                     printf("[video] tvos: erro do player %d (%d)\n", a, b); break;
    case EV_TAMANHO: largura = a; altura = b; break;
    case EV_BUFFER:
      if (a < 100 && !bufferando) { bufferando = 1; bufferDesde = SDL_GetTicks(); }
      else if (a >= 100) bufferando = 0;
      break;
    case EV_PRIMEIRO_QUADRO: marco("video: primeiro quadro (tvos)"); primeiroQuadro = 1; break;
    case EV_SUPERFICIE_ESTAVEL: superficieEstavel = 1; break;
    case EV_AUDIO_SEM_DECODER: semDecoderAudio = 1; break;
    default: break;
  }
  if (tipo != EV_BUFFER) { printf("[video] tvos evento %d (%d, %d)\n", tipo, a, b); fflush(stdout); }
}

// --- player externo com legendas ----------------------------------------------
// A busca de legendas dos add-ons sai quando o titulo abre (app.c); quase
// sempre ja terminou quando a pessoa aperta Play. Se nao, espera ate
// EXT_ESPERA_MS e manda o que houver.
#define EXT_ESPERA_MS 8000u
#define EXT_MAX_LEG 8
static struct { int qual; char url[4096]; char titulo[160]; double pos; Uint32 desde; } ext;
static int extPendente;

void nv_tvos_externo_pedir(int qual, const char *url, const char *titulo, double posSeg) {
  ext.qual = qual;
  snprintf(ext.url, sizeof ext.url, "%s", url ? url : "");
  snprintf(ext.titulo, sizeof ext.titulo, "%s", titulo ? titulo : "");
  ext.pos = posSeg;
  ext.desde = SDL_GetTicks();
  extPendente = 1;
  printf("[externo] pedido: player %d, legendas %s\n", qual,
         ajustes_player_apple_legendas() ? (addons_legendas_prontas() ? "prontas" : "aguardando") : "desligadas");
  fflush(stdout);
}

static int extIdiomaQuer(const char *pref) {
  return pref && pref[0] && strcasecmp(pref, "none") && strcasecmp(pref, "off");
}

static void extConcluir(void) {
  static Legenda v[LEG_MAX];
  char *subs = NULL;
  size_t usado = 0, cap = 0;
  int n = 0, i, mandadas = 0, passo;
  const char *prefs[2];
  extPendente = 0;
  if (ajustes_player_apple_legendas()) {
    n = addons_legendas_copiar(v, LEG_MAX, NULL, NULL);
    prefs[0] = ling_legenda(); prefs[1] = ling_legenda2();
    cap = (size_t)EXT_MAX_LEG * 1100 + 1;
    subs = calloc(1, cap);
    // Idioma 1, depois idioma 2; sem idioma escolhido, as primeiras da lista.
    for (passo = 0; subs && passo < 3 && mandadas < EXT_MAX_LEG; passo++) {
      // Como o NuvioTVOS: as do idioma preferido na frente (o VLC so le a
      // primeira), e o resto da lista completa ate 8, para o player externo
      // ter o que mostrar mesmo quando nada casa com o idioma escolhido.
      int limite = passo == 0 ? 6 : passo == 1 ? 2 : EXT_MAX_LEG;
      int nesta = 0;
      if (passo < 2 && !extIdiomaQuer(prefs[passo])) continue;
      for (i = 0; i < n && nesta < limite && mandadas < EXT_MAX_LEG; i++) {
        size_t k;
        if (!v[i].url[0] || strncmp(v[i].url, "http", 4)) continue;
        if (passo < 2 && !(v[i].idioma[0] && ling_casa(v[i].idioma, prefs[passo]))) continue;
        if (strstr(subs, v[i].url)) continue;
        k = strlen(v[i].url);
        if (usado + k + 2 > cap) break;
        if (usado) subs[usado++] = '\n';
        memcpy(subs + usado, v[i].url, k); usado += k; subs[usado] = 0;
        nesta++; mandadas++;
      }
    }
  }
  printf("[externo] entregando ao player %d com %d legenda(s) de %d\n", ext.qual, mandadas, n);
  fflush(stdout);
  nv_tvos_player_externo(ext.qual, ext.url, ext.titulo, ext.pos, subs ? subs : "");
  free(subs);
}

static void extBombear(void) {
  if (!extPendente) return;
  Uint32 passou = SDL_GetTicks() - ext.desde;
  // "Prontas" com lista vazia logo no pedido e a busca do titulo que ainda
  // nao saiu (ou a do episodio anterior): espera mais um pouco por ela.
  if (!ajustes_player_apple_legendas() || passou >= EXT_ESPERA_MS ||
      (addons_legendas_prontas() && (addons_n_legendas() > 0 || passou >= 3000u)))
    extConcluir();
}

// --- video.h (C -> Swift) ----------------------------------------------------
static int proximoTrailer = 0;   // marcado pelo trailer.c, vale para a proxima fonte
static int sessaoTrailer = 0;    // a fonte atual e um trailer (tambem nas reaberturas)
void video_tvos_trailer_marcar(int sim) { proximoTrailer = sim ? 1 : 0; }

int  video_iniciar(void) {
  if (!travaLeg) travaLeg = SDL_CreateMutex();
  return 1;
}
int  video_iniciar_auto(void) { return video_iniciar(); }
int  video_registro_negado(void) { return 0; }

static int abrirSessao(int inicioMs) {
  ativo = 1; superficieEstavel = 0; prontoLoad = primeiroQuadro = falhou = terminou = tocando = 0;
  velEnviada = 100;
  largura = altura = durMs = posMs = 0; bufferando = 1; bufferDesde = SDL_GetTicks();
  tocandoDesde = 0; semDecoderAudio = 0; erroTxt[0] = 0; reconErroVideo = 0;
  pausaPedida = pausaVista = 0;
  hdrAtual = "none"; dvAtual = atmosAtual = 0;
  nAudio = nLeg = 0; audioAtual = 0; legAtual = -1; legAte = 0;
  nNovasA = nNovasL = 0;
  temEnv = 0;
  if (!travaLeg) travaLeg = SDL_CreateMutex();
  {
    unsigned geracao = novaRetomada(-1);
    if (inicioMs > 0) estadoRetomada(0);
    nvp_trailer(sessaoTrailer);
    nvp_abrir(urlAtual, cabecalhos, inicioMs, (int)geracao);
  }
  return 1;
}

int video_tocar_retomada(const char *u, double segundos, double pct) {
  int inicioMs = isfinite(segundos) && segundos > 0.0 && segundos <= INT_MAX / 1000.0
    ? (int)(segundos * 1000.0) : 0;
  (void)pct;   // percentual: o player.c busca depois do pronto (estado -1)
  snprintf(urlAtual, sizeof urlAtual, "%s", u ? u : "");
  capmkv_iniciar(urlAtual);
  nv_recon_zerar(&recon);
  reconPermitida = reconProxima; reconProxima = 0;
  sessaoTrailer = proximoTrailer; proximoTrailer = 0;
  reconIniciou = 0; reconErroPend = 0;
  reconAudio = reconLeg = -1; reconFaixasPend = 0; reconBuscarMs = -1;
  return abrirSessao(inicioMs);
}
int video_tocar_posicao(const char *u, double segundos) { return video_tocar_retomada(u, segundos, 0.0); }
int video_tocar(const char *u) { return video_tocar_posicao(u, 0.0); }

void video_definir_reconexao(int sim) { reconProxima = sim ? 1 : 0; }
// 2.0.6: reabrir a fonte VOD no lugar (Android); o AetherEngine ja reconecta
// sozinho, entao aqui o pedido nao e aceito e o app segue o caminho normal.
int  video_recarregar(void) { return 0; }
int  video_reconectando(void) {
  return nv_recon_ativa(&recon) && (recon.pendente || !prontoLoad) ? recon.tentativa : 0;
}

void video_bombear(void) {
  double pos;
  extBombear();
  if (ativo) nvp_bombear();   // o Swift le o motor e chama os nv_tvos_*
  pos = video_pos();
  if (ativo && prontoLoad && velEnviada != velPedida) {
    velEnviada = velPedida;
    nvp_velocidade(velEnviada);
    vel_log(velEnviada, "enviado ao AetherEngine");
  }
  if (prontoLoad && pos > 0.5) reconIniciou = 1;
  if (prontoLoad && reconBuscarMs < 0) nv_recon_progresso(&recon, pos);
  if (reconBuscarMs >= 0 && prontoLoad && tocando) {
    nvp_buscar(reconBuscarMs);
    printf("[video] reconexao: retomado em %ds\n", reconBuscarMs / 1000);
    fflush(stdout);
    reconBuscarMs = -1;
  }
  if (reconErroPend) {
    int antes = recon.tentativa;
    int rede = erroDeRede(reconErroCod);
    reconErroPend = 0;
    if (reconPermitida && urlAtual[0] && (reconIniciou || recon.tentativa) &&
        nv_recon_erro(&recon, rede, SDL_GetTicks(), pos)) {
      if (!antes) { reconAudio = audioAtual; reconLeg = legAtual; }
      if (recon.tentativa != antes) {
        printf("[video] conexao caiu (%d): tentativa %d/%d, espera %us\n",
               reconErroCod, recon.tentativa, NV_RECON_MAX,
               nv_recon_espera_ms(recon.tentativa) / 1000u);
        fflush(stdout);
      }
      bufferando = 0;
    } else {
      if (recon.esgotou) { printf("[video] reconexao: desistiu depois de %d tentativas\n", NV_RECON_MAX); fflush(stdout); }
      falhou = 1;
    }
  }
  if (nv_recon_vencida(&recon, SDL_GetTicks())) {
    printf("[video] reconectando: alvo %.0fs, tentativa %d\n", recon.alvo, recon.tentativa);
    fflush(stdout);
    reconFaixasPend = 1;
    reconBuscarMs = recon.alvo > 1.0 ? (int)(recon.alvo * 1000.0) : -1;
    abrirSessao(0);
  }
}
void video_parar(void) {
  novaRetomada(-1);
  capmkv_zerar();
  nv_recon_zerar(&recon);
  reconErroPend = 0; reconErroVideo = 0; reconFaixasPend = 0; reconBuscarMs = -1;
  if (ativo) nvp_parar();
  ativo = prontoLoad = primeiroQuadro = tocando = 0; superficieEstavel = 0;
  pausaPedida = pausaVista = 0;
}
void video_pausar(int p) { pausaVista = 0; pausaPedida = p ? 1 : 0; nvp_pausar(p ? 1 : 0); }
int video_pausa_confirmada(void) {
  return pausaPedida && pausaVista && !tocando && ativo && prontoLoad && primeiroQuadro &&
         !falhou && !terminou && !video_reconectando();
}

void video_volume(int pct) { nvp_volume(pct); }
void video_buscar(double s) {
  posMs = (int)(s * 1000.0);
  nvp_buscar(posMs);
  terminou = 0;
}
static void janelaEnviar(int x, int y, int w, int h, int encaixa) {
  envX = x; envY = y; envW = w; envH = h; envEnc = encaixa; temEnv = 1;
  nvp_janela(x, y, w, h, encaixa);
}
static void janelaSeMudou(int x, int y, int w, int h, int encaixa) {
  if (temEnv && x == envX && y == envY && w == envW && h == envH && encaixa == envEnc) return;
  janelaEnviar(x, y, w, h, encaixa);
}
void video_janela(int x, int y, int w, int h) { janelaSeMudou(x, y, w, h, 1); }

// Recorte de fonte pelo retangulo de destino ampliado (mesma conta do Android):
// a view do player pode sair da tela e ter origem negativa; a janela recorta.
static int ultX, ultY, ultW, ultH, temUlt;
void video_janela_fonte(int sx, int sy, int sw, int sh, int dx, int dy, int dw, int dh) {
  double qw = largura, qh = altura, ex, ey;
  int X, Y, W, H;
  if (qw < 2.0 || qh < 2.0 || sw <= 0 || sh <= 0) { temUlt = 0; video_janela(dx, dy, dw, dh); return; }
  if (sx <= 0 && sy <= 0 && sw >= (int)qw && sh >= (int)qh) { temUlt = 0; janelaSeMudou(dx, dy, dw, dh, 0); return; }
  ex = (double)dw / (double)sw;
  ey = (double)dh / (double)sh;
  W  = (int)(qw * ex + 0.5);
  H  = (int)(qh * ey + 0.5);
  X  = (int)(dx - sx * ex + (dx - sx * ex < 0 ? -0.5 : 0.5));
  Y  = (int)(dy - sy * ey + (dy - sy * ey < 0 ? -0.5 : 0.5));
  ultX = X; ultY = Y; ultW = W; ultH = H; temUlt = 1;
  janelaSeMudou(X, Y, W, H, 0);
}
int  video_recorte_fonte(void) { return 1; }
void video_recorte_reaplicar(void) { if (temUlt) janelaEnviar(ultX, ultY, ultW, ultH, 0); }
void video_escala_definir(int sw, int sh) { (void)sw; (void)sh; }

const char *video_url_atual(void) { return urlAtual; }
double video_pos(void) { return prontoLoad ? posMs / 1000.0 : 0; }
double video_duracao(void) { return durMs / 1000.0; }
double video_creditos(void) { return capmkv_creditos(video_duracao()); }
double video_buffer_fim(void) { return 0; }
unsigned video_bufferando_ms(void) {
  if (nv_recon_ativa(&recon)) return 0;
  return bufferando ? SDL_GetTicks() - bufferDesde : 0;
}
void video_definir_dv(int dv) { (void)dv; }
void video_definir_cabecalhos(const char *c) { snprintf(cabecalhos, sizeof cabecalhos, "%s", c ? c : ""); }
const char *video_cabecalhos(void) { return cabecalhos; }
void video_definir_mp4(int m) { (void)m; }
int  video_tocando(void) { return tocando; }
int  video_pronto(void) {
  Uint32 desde;
  if (!prontoLoad) return 0;
  if (primeiroQuadro) return 1;
  desde = tocandoDesde;
  return desde && tocando && SDL_GetTicks() - desde >= TVOS_FURO_PRAZO_MS;
}
int  video_ativo(void) { return ativo; }
int  video_superficie_estavel(void) { return superficieEstavel; }
int  video_quadro_visto(void) { return primeiroQuadro; }
int  video_falhou(void) { return falhou; }
int  video_audio_nao_suportado(void) { return semDecoderAudio; }
int  video_seek_desistiu(void) { return 0; }
int  video_terminou(void) { return terminou; }
int  video_conflito_recurso(void) { return 0; }
const char *video_erro_texto(void) { return falhou ? erroTxt : ""; }
int video_erro_decoder_codigo(void) { return falhou && reconErroVideo ? reconErroCod : 0; }
int  video_decoder_anunciou(void) { return 1; }

int  video_n_audio(void) { return nAudio; }
int  video_n_legenda(void) { return nLeg; }
const VideoFaixa *video_audio(int i) { return (i >= 0 && i < nAudio) ? &faixaAudio[i] : 0; }
const VideoFaixa *video_legenda(int i) { return (i >= 0 && i < nLeg) ? &faixaLeg[i] : 0; }
int  video_legenda_ordinal_mkv(int i) { return (i >= 0 && i < nLeg) ? faixaLeg[i].ordinalMkv : -1; }
int  video_mkv_sondado(void) { return 2; }
void video_sondar_mkv_agora(void) {}
int  video_audio_atual(void) { return audioAtual; }
int  video_legenda_atual(void) { return legAtual; }
void video_escolher_audio(int i) {
  if (i < 0 || i >= nAudio) return;
  audioAtual = i;
  nvp_escolher(0, faixaAudio[i].numero);
}
void video_escolher_legenda(int i) {
  if (i >= nLeg) return;
  legAtual = i;
  if (travaLeg) { SDL_LockMutex(travaLeg); legTexto[0] = 0; legAte = 0; SDL_UnlockMutex(travaLeg); }
  nvp_escolher(1, i >= 0 ? faixaLeg[i].numero : -1);
}
int  video_legenda_nativa(char *d, int t) {
  if (!d || t < 2) return 0;
  d[0] = 0;
  if (!ativo || legAtual < 0 || !travaLeg) return 0;
  SDL_LockMutex(travaLeg);
  if (legTexto[0] && (Sint32)(legAte - SDL_GetTicks()) > 0) snprintf(d, (size_t)t, "%s", legTexto);
  SDL_UnlockMutex(travaLeg);
  return d[0] != 0;
}
void video_legenda_externa(const char *u) { (void)u; }
void video_legenda_estilo(const VideoLegendaEstilo *e) {
  static int ultAtraso = 0x7fffffff;
  if (!e || e->atrasoMs == ultAtraso) return;
  ultAtraso = e->atrasoMs;
  nvp_escolher(2, e->atrasoMs);
}
int  video_tem_atmos(void) { return atmosAtual; }
int  video_tem_dolby_vision(void) { return dvAtual; }
const char *video_hdr(void) { return (const char *)hdrAtual; }
int  video_largura(void) { return largura; }
int  video_altura(void) { return altura; }
int  video_pode_forcar_sdr(void) { return 0; }
int  video_velocidade_suportada(void) { return !velRecusada; }
void video_velocidade(int c) { if (!velRecusada) velPedida = (c <= 0 || c > 400) ? 100 : c; }
int  video_velocidade_atual(void) { return velRecusada ? 100 : velPedida; }
void video_velocidade_recusada(void) { velRecusada = 1; velPedida = 100; }
int  video_velocidade_bloqueada(void) { return 0; }
void video_forcar_sdr(void) {}
void video_encerrar(void) { video_parar(); }
#endif
