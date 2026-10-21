// Included by gfx.c after its internal state declarations. This adapter only
// serializes presentation values: no UIKit work, text drawing or image effects.
#ifdef NV_TVOS
static void swiftSceneRect(GfxRect r, GLuint tex, GfxModo mode, float focus,
    float px, float py, float radius, float red, float green, float blue, float alpha, int dual) {
  NvSceneCommand c = {0};
  c.mode = mode; c.texture = tex; c.rect = (NvSceneRect){r.x, r.y, r.w, r.h};
  c.color = (NvSceneColor){red, green, blue, alpha * gfx_opacidade_grupo};
  if (mode == GFX_HERO || mode == GFX_HERO_CHEIO || mode == GFX_DETALHE || mode == GFX_RETRATO ||
      mode == GFX_EDITORIAL || mode == GFX_CEU || mode == GFX_VITRINE || mode == GFX_VITRINE_DIN ||
      mode == GFX_HERO_CAM || mode == GFX_HERO_CHEIO_CAM || mode == GFX_JANELA || mode == GFX_AMBIENTE)
    c.background = (NvSceneColor){NV_COR_FUNDO_R, NV_COR_FUNDO_G, NV_COR_FUNDO_B, 1};
  c.focus = focus; c.parx = px; c.pary = py; c.radius = radius; c.aspect = gfx_tex_aspect_atual;
  c.slide = gfx_desliza_atual;
  if (mode == GFX_CARD || mode == GFX_CARD_HERO) {
    c.border = gfx_borda_foco_atual; c.sweep = gfx_varre_atual;
    c.reflect = ajustes_profundidade() ? ajustes_profundidade_brilho() : 0;
    if (mode == GFX_CARD_HERO)
      c.grad0 = (NvSceneColor){gfx_card_heroi_veu_atual[0], gfx_card_heroi_veu_atual[1],
                              gfx_card_heroi_veu_atual[2], gfx_card_heroi_veu_atual[3]};
  }
  if (mode == GFX_HOLOFOTE || mode == GFX_PALCO_CHAO || mode == GFX_PALCO_ARTE)
    c.veil = (NvSceneColor){nv_acento_viva[0], nv_acento_viva[1], nv_acento_viva[2], 1};
  const float *uv = mode == GFX_TEXTURA ? txUv : gfx_janela_atual;
  c.uv = (NvSceneRect){uv[0], uv[1], uv[2], uv[3]};
  NvSceneColor *grad[3] = {&c.grad0, &c.grad1, &c.grad2};
  if (mode == GFX_COR_GRAD || mode == GFX_ANEL_GRAD)
    for (int i = 0; i < 3; i++) *grad[i] = (NvSceneColor){nv_grad_viva[i][0], nv_grad_viva[i][1], nv_grad_viva[i][2], 1};
  NvSceneColor *ambient[4] = {&c.ambient0, &c.ambient1, &c.ambient2, &c.ambient3};
  if (mode == GFX_AMBIENTE)
    for (int i = 0; i < 4; i++) *ambient[i] = (NvSceneColor){nv_ambiente_viva[i][0], nv_ambiente_viva[i][1], nv_ambiente_viva[i][2], 1};
  if (mode == GFX_ESQUELETO) c.time = nv_tempo_viva;
  c.flags = (gfx_card_forcar_cover_atual ? 2u : 0u) | (gfx_card_veu_tela_atual ? 4u : 0u) |
            (gfx_arte_opaca_atual ? 8u : 0u) | (!blendLigado ? 32u : 0u);
  if ((mode == GFX_CARD || mode == GFX_CARD_HERO) && !gfx_veu_na_arte) {
    c.bottom0 = gfx_veu_card_atual[0]; c.bottomAlpha0 = gfx_veu_card_atual[1];
    c.bottom1 = gfx_veu_card_atual[2]; c.bottomAlpha1 = gfx_veu_card_atual[3];
  }
  if (dual) { c.flags |= 64; c.texture2 = camTexB; c.aspect2 = camAspB; c.alpha2 = camAlfaB * gfx_opacidade_grupo; }
  if (giroOn) { c.rotation = giroLayout[0]; c.centerX = giroLayout[1] * escAtiva; c.centerY = giroLayout[2] * escAtiva; }
  float x0 = r.x + r.w * subAtual[0], y0 = r.y + r.h * subAtual[1];
  float x1 = r.x + r.w * subAtual[2], y1 = r.y + r.h * subAtual[3];
  if (recorteAtivo) {
    float ex = (float)telaW / NV_TELA_W, ey = (float)telaH / NV_TELA_H;
    float sx0 = (float)recorteBox[0] / ex, sy0 = NV_TELA_H - (float)(recorteBox[1] + recorteBox[3]) / ey;
    float sx1 = sx0 + (float)recorteBox[2] / ex, sy1 = sy0 + (float)recorteBox[3] / ey;
    if (miniAtiva) {
      sx0 = miniX0 + (float)recorteBox[0] / miniEsc;
      sy0 = miniY0 + (float)(miniPxH - recorteBox[1] - recorteBox[3]) / miniEsc;
      sx1 = sx0 + (float)recorteBox[2] / miniEsc; sy1 = sy0 + (float)recorteBox[3] / miniEsc;
    }
    x0 = fmaxf(x0, sx0); y0 = fmaxf(y0, sy0); x1 = fminf(x1, sx1); y1 = fminf(y1, sy1);
  }
  c.flags |= 1; c.clip = (NvSceneRect){x0, y0, fmaxf(0, x1-x0), fmaxf(0, y1-y0)};
  if (miniAtiva) {
    float sx = miniEsc * NV_TELA_W / miniPxW, sy = miniEsc * NV_TELA_H / miniPxH;
    c.rect = (NvSceneRect){(r.x-miniX0)*sx, (r.y-miniY0)*sy, r.w*sx, r.h*sy};
    c.clip = (NvSceneRect){(x0-miniX0)*sx, (y0-miniY0)*sy, fmaxf(0,x1-x0)*sx, fmaxf(0,y1-y0)*sy};
    c.centerX = (c.centerX-miniX0)*sx; c.centerY = (c.centerY-miniY0)*sy;
  }
  nvscene_draw(&c);
}
#endif
