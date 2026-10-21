// Apple TV (tvOS): ponte entre o nucleo C e a camada nativa (tvos/*.m, *.swift).
#ifndef NV_TVOS_H
#define NV_TVOS_H
#ifdef NV_TVOS
// Abre uma URL no sistema (apps externos: Infuse, VLC, YouTube...).
void nv_tvos_abrir_url(const char *url);
// Pasta de dados persistente do app (Caches/nuvio). Nunca NULL.
const char *nv_tvos_dir_dados(void);

// --- player (Swift, NvPlayer.swift; motor AetherEngine do NuvioTVOS) ---------
// Mesmo contrato do NvPlayer.kt do Android: o C pede, o Swift avisa pelos
// nv_tvos_* abaixo (video_tvos.c). Tudo no fio principal (o SDL roda nele).
void nvp_abrir(const char *url, const char *cabecalhos, int inicioMs, int geracao);
// 1 = o proximo nvp_abrir e um trailer: sem "Ajustar a taxa de quadros" (a
// troca de modo da TV apaga a tela por 1 a 3 s antes de cada trailer).
void nvp_trailer(int sim);
// O que o proximo nvp_abrir toca (player.c), para o "Tocando agora" do sistema:
// Central de Controle, o controle do iPhone e o cartao de informacoes da TV.
void nvp_info(const char *titulo, const char *subtitulo, const char *arte);
// A fileira Continuar assistindo para o Top Shelf (NvTopShelf.m): linhas com
// campos separados por TAB, ver catalogo.c. So grava quando muda.
void nv_tvos_topshelf(const char *texto);

// Teclado do sistema (NvTexto.m): abre com o texto atual; o texto inteiro e o
// fim voltam por texto_sistema_ponte_valor / texto_sistema_ponte_fim.
void nv_tvos_teclado_abrir(const char *atual);
void nv_tvos_teclado_fechar(void);
void nvp_parar(void);
void nvp_pausar(int pausado);
void nvp_buscar(int ms);
void nvp_volume(int pct);
void nvp_janela(int x, int y, int w, int h, int encaixa);
void nvp_escolher(int tipo, int valor);   // 0 audio (id), 1 legenda (id, -1 desliga), 2 atraso ms
void nvp_velocidade(int centesimos);
void nvp_bombear(void);

// Player externo (Infuse, VLC, Outplayer, nPlayer, VidHub, SenPlayer, Native
// Player): 1 = entregue ao app, 0 = nao instalado/URL invalida (toca aqui).
// `qual` = ajustes_player_apple() (1..7).
// `legendas`: URLs separadas por '\n' (pode ser vazio).
int nv_tvos_player_externo(int qual, const char *url, const char *titulo, double posSeg,
                           const char *legendas);
// 1 se o app do player `qual` esta instalado (canOpenURL).
int nv_tvos_player_instalado(int qual);
// player.c: entrega ao player externo assim que as legendas dos add-ons
// chegarem (ou ja, com o ajuste desligado). O video_bombear conclui.
void nv_tvos_externo_pedir(int qual, const char *url, const char *titulo, double posSeg);

// Swift -> C (video_tvos.c)
void nv_tvos_ev(int tipo, int a, int b);
void nv_tvos_faixa(int tipo, int id, const char *lingua, int flags, const char *nome,
                   const char *codec, int canais);
void nv_tvos_faixas_fim(int selAudio, int selLeg);
void nv_tvos_legenda(const char *texto, int durMs);
void nv_tvos_pos(int ms);
void nv_tvos_hdr(const char *hdr, int dv, int atmos);
void nv_tvos_retomada(int geracao, int aceita);
void nv_tvos_erro_texto(const char *texto);
#endif
#endif
