// Nuvio Legacy on Apple TV: the system keyboard for the core's text fields.
//
// Same idea as NuvioTV's HiddenSearchTextField: an invisible UITextField that
// can never take the focus becomes first responder, and tvOS shows its own
// keyboard (Siri dictation, the "type on your iPhone" notification). Every
// change sends the WHOLE text to the core (entrada_texto.c mirrors it into
// the field); Done or Menu end the session.
//
// SDL's own UITextField (SDL_StartTextInput) is not used: next to the focus
// grid of NvRemote.m it got the keyboard about once in ten tries and the text
// typed did not reach the field.
#import <UIKit/UIKit.h>
#include <stdio.h>

void texto_sistema_ponte_valor(const char *valor);
void texto_sistema_ponte_fim(int confirmou);

@interface NvCampo : UITextField
@end
@implementation NvCampo
- (BOOL)canBecomeFocused { return NO; }
@end

@interface NvTextoDelegado : NSObject <UITextFieldDelegate>
@property (nonatomic) BOOL aberto, confirmou;
@property (nonatomic) int tentativas;
@end

static NvCampo *gCampo;
static NvTextoDelegado *gDelegado;

static void NvLog(NSString *s) { printf("[texto] tvos: %s\n", s.UTF8String); fflush(stdout); }

@implementation NvTextoDelegado
- (void)mudou:(UITextField *)t {
    if (!self.aberto) return;
    texto_sistema_ponte_valor(t.text.UTF8String ?: "");
}
- (BOOL)textFieldShouldReturn:(UITextField *)t {
    self.confirmou = YES;
    [t resignFirstResponder];
    return YES;
}
- (void)textFieldDidBeginEditing:(UITextField *)t {
    NvLog(@"teclado na tela");
}
- (void)textFieldDidEndEditing:(UITextField *)t {
    if (!self.aberto) return;
    self.aberto = NO;
    texto_sistema_ponte_valor(t.text.UTF8String ?: "");
    texto_sistema_ponte_fim(self.confirmou ? 1 : 0);
    NvLog(self.confirmou ? @"fechou (concluir)" : @"fechou (menu)");
}
- (void)pedirTeclado {
    if (!self.aberto || gCampo.isFirstResponder) return;
    if ([gCampo becomeFirstResponder]) return;
    if (++self.tentativas < 6) {
        // the window or its first responder may still be settling (a focus move
        // in flight): try again a moment later
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self pedirTeclado]; });
        return;
    }
    NvLog(@"o teclado nao abriu");
    self.aberto = NO;
    texto_sistema_ponte_fim(0);
}
@end

static UIView *NvRaiz(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)s).windows)
                if (w.rootViewController) return w.rootViewController.view;
    return nil;
}

void nv_tvos_teclado_abrir(const char *atual) {
    NSString *texto = [NSString stringWithUTF8String:atual ? atual : ""] ?: @"";
    dispatch_block_t abrir = ^{
        UIView *raiz = NvRaiz();
        if (!raiz) { NvLog(@"sem janela"); texto_sistema_ponte_fim(0); return; }
        if (!gDelegado) gDelegado = [NvTextoDelegado new];
        if (!gCampo) {
            gCampo = [[NvCampo alloc] initWithFrame:CGRectMake(-4000, -4000, 1, 1)];
            gCampo.delegate = gDelegado;
            gCampo.backgroundColor = UIColor.clearColor;
            gCampo.textColor = UIColor.clearColor;
            gCampo.tintColor = UIColor.clearColor;
            gCampo.returnKeyType = UIReturnKeySearch;
            gCampo.keyboardAppearance = UIKeyboardAppearanceDark;
            gCampo.autocorrectionType = UITextAutocorrectionTypeNo;
            gCampo.autocapitalizationType = UITextAutocapitalizationTypeNone;
            [gCampo addTarget:gDelegado action:@selector(mudou:) forControlEvents:UIControlEventEditingChanged];
        }
        if (gCampo.superview != raiz) [raiz addSubview:gCampo];
        gCampo.text = texto;
        gDelegado.confirmou = NO;
        gDelegado.tentativas = 0;
        gDelegado.aberto = YES;
        NvLog([NSString stringWithFormat:@"abrindo (%lu caracteres)", (unsigned long)texto.length]);
        // next turn of the run loop, as NuvioTV does: the core is mid-frame here
        dispatch_async(dispatch_get_main_queue(), ^{ [gDelegado pedirTeclado]; });
    };
    if (NSThread.isMainThread) abrir(); else dispatch_async(dispatch_get_main_queue(), abrir);
}

void nv_tvos_teclado_fechar(void) {
    dispatch_block_t fechar = ^{
        if (!gDelegado.aberto) return;
        gDelegado.aberto = NO;   // the core already closed: no end event back
        [gCampo resignFirstResponder];
        NvLog(@"fechado pelo app");
    };
    if (NSThread.isMainThread) fechar(); else dispatch_async(dispatch_get_main_queue(), fechar);
}

// NvRemote.m: the focus grid keeps its hands off while the keyboard is up.
BOOL nv_tvos_teclado_ativo(void) { return gDelegado.aberto; }
