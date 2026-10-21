// Nuvio Legacy: one native gesture or physical press -> one navigation step.
// The C/SDL UI has no UIKit poster views. A single stable focus receiver takes
// remote input; focus changes themselves NEVER produce arrow keys. In particular,
// no invisible grid, focus momentum or delayed recentering can move the C focus.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <SDL2/SDL.h>
#include "NvRemoteTiming.h"

static NvRemoteTiming gTiming;
static BOOL gButtons[SDL_NUM_SCANCODES];
static int gSintetico;
BOOL nv_tvos_teclado_ativo(void); // NvTexto.m
// Optional in the standalone remote regression harness.
extern void *nvui_focus_environment(void) __attribute__((weak_import));
extern int nvui_owns_focus(void) __attribute__((weak_import));

static void NvChave(SDL_Scancode sc, BOOL desce) {
    SDL_Event e;
    SDL_zero(e);
    e.type = desce ? SDL_KEYDOWN : SDL_KEYUP;
    e.key.state = desce ? SDL_PRESSED : SDL_RELEASED;
    e.key.keysym.scancode = sc;
    e.key.keysym.sym = SDL_GetKeyFromScancode(sc);
    SDL_Window *w = SDL_GetKeyboardFocus();
    e.key.windowID = w ? SDL_GetWindowID(w) : 0;
    gSintetico++;
    SDL_PushEvent(&e);
    gSintetico--;
}
static void NvTecla(SDL_Scancode sc) { NvChave(sc, YES); NvChave(sc, NO); }
static void NvBotaoEstado(SDL_Scancode sc, BOOL down) {
    if (gButtons[sc] == down) return;
    gButtons[sc] = down;
    NvChave(sc, down);
}
static void NvSoltarBotoes(void) {
    for (int sc = 0; sc < SDL_NUM_SCANCODES; sc++)
        if (gButtons[sc]) NvBotaoEstado((SDL_Scancode)sc, NO);
    NvRemoteTimingReset(&gTiming);
}
// One shared key sink for both native controls and the legacy-screen receiver.
void nvui_key(int key, int down) {
    const SDL_Scancode keys[] = { SDL_SCANCODE_UP, SDL_SCANCODE_DOWN,
        SDL_SCANCODE_LEFT, SDL_SCANCODE_RIGHT, SDL_SCANCODE_RETURN,
        SDL_SCANCODE_ESCAPE, SDL_SCANCODE_PAUSE };
    if (key < 0 || key >= (int)(sizeof keys / sizeof *keys)) return;
    NvBotaoEstado(keys[key], down != 0);
}
static BOOL NvDirecao(SDL_Scancode sc) {
    return sc == SDL_SCANCODE_UP || sc == SDL_SCANCODE_DOWN ||
           sc == SDL_SCANCODE_LEFT || sc == SDL_SCANCODE_RIGHT;
}
static SDL_Scancode NvBotao(UIPressType type) {
    switch (type) {
        case UIPressTypeUpArrow:   return SDL_SCANCODE_UP;
        case UIPressTypeDownArrow: return SDL_SCANCODE_DOWN;
        case UIPressTypeLeftArrow: return SDL_SCANCODE_LEFT;
        case UIPressTypeRightArrow:return SDL_SCANCODE_RIGHT;
        case UIPressTypeSelect:    return SDL_SCANCODE_RETURN;
        case UIPressTypeMenu:      return SDL_SCANCODE_ESCAPE;
        case UIPressTypePlayPause: return SDL_SCANCODE_PAUSE;
        default:                  return SDL_SCANCODE_UNKNOWN;
    }
}

@interface NvRemoteView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) NSTimer *repeatTimer;
- (void)cancelarEntrada;
@end
static NvRemoteView *gRemote;

@implementation NvRemoteView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UISwipeGestureRecognizerDirection directions[] = {
            UISwipeGestureRecognizerDirectionUp, UISwipeGestureRecognizerDirectionDown,
            UISwipeGestureRecognizerDirectionLeft, UISwipeGestureRecognizerDirectionRight
        };
        for (unsigned i = 0; i < 4; i++) {
            // UIKit supplies the touch dead zone and emits ONCE per gesture,
            // regardless of swipe velocity or how long focus momentum lasts.
            UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc]
                initWithTarget:self action:@selector(deslizar:)];
            swipe.direction = directions[i];
            swipe.allowedPressTypes = @[]; // button presses have their own path
            swipe.delegate = self;
            [self addGestureRecognizer:swipe];
        }
    }
    return self;
}
- (BOOL)canBecomeFocused { return !nvui_owns_focus || !nvui_owns_focus(); }
- (BOOL)recebeEntrada {
    return self.window && UIApplication.sharedApplication.applicationState == UIApplicationStateActive &&
           !nv_tvos_teclado_ativo() && self.window.windowScene.focusSystem.focusedItem == self;
}
- (void)cancelarEntrada {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
    NvSoltarBotoes();
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self cancelarEntrada];
}
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    if (context.previouslyFocusedView == self && context.nextFocusedView != self)
        [self cancelarEntrada];
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    return [self recebeEntrada] && !gTiming.direction && !gButtons[SDL_SCANCODE_RETURN];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    // Cooperate with UIKit's focus pan, but let the four discrete swipes compete
    // with each other so a diagonal gesture cannot produce two directions.
    return [other isKindOfClass:UIPanGestureRecognizer.class];
}
- (void)deslizar:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || ![self recebeEntrada] ||
        gTiming.direction || gButtons[SDL_SCANCODE_RETURN]) return;
    SDL_Scancode sc;
    switch (gesture.direction) {
        case UISwipeGestureRecognizerDirectionUp:    sc = SDL_SCANCODE_UP; break;
        case UISwipeGestureRecognizerDirectionDown:  sc = SDL_SCANCODE_DOWN; break;
        case UISwipeGestureRecognizerDirectionLeft:  sc = SDL_SCANCODE_LEFT; break;
        case UISwipeGestureRecognizerDirectionRight: sc = SDL_SCANCODE_RIGHT; break;
        default: return;
    }
    NvTecla(sc);
    printf("[remote] swipe %d: one step\n", (int)sc);
}
- (void)iniciarRepeticao {
    if (self.repeatTimer) return;
    __weak NvRemoteView *weakSelf = self;
    self.repeatTimer = [NSTimer timerWithTimeInterval:1.0 / 60.0 repeats:YES block:^(NSTimer *timer) {
        NvRemoteView *view = weakSelf;
        if (![view recebeEntrada]) { [view cancelarEntrada]; return; }
        int direction = NvRemoteTimingRepeat(&gTiming, SDL_GetTicks());
        if (direction) NvTecla((SDL_Scancode)direction);
    }];
    self.repeatTimer.tolerance = 0.005;
    [NSRunLoop.mainRunLoop addTimer:self.repeatTimer forMode:NSRunLoopCommonModes];
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *rest = [NSMutableSet set];
    for (UIPress *press in presses) {
        SDL_Scancode sc = NvBotao(press.type);
        if (sc == SDL_SCANCODE_UNKNOWN) { [rest addObject:press]; continue; }
        if (![self recebeEntrada]) continue;
        if (NvDirecao(sc)) {
            if (NvRemoteTimingPress(&gTiming, sc, SDL_GetTicks())) NvTecla(sc);
            [self iniciarRepeticao];
        } else {
            NvBotaoEstado(sc, YES);
        }
    }
    // Never forward handled arrows: SDL's parent view would send the same key again.
    if (rest.count) [super pressesBegan:rest withEvent:event];
}
- (void)pressesChanged:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *rest = [NSMutableSet set];
    for (UIPress *press in presses)
        if (NvBotao(press.type) == SDL_SCANCODE_UNKNOWN) [rest addObject:press];
    if (rest.count) [super pressesChanged:rest withEvent:event];
}
- (void)soltar:(NSSet<UIPress *> *)presses rest:(NSMutableSet *)rest {
    for (UIPress *press in presses) {
        SDL_Scancode sc = NvBotao(press.type);
        if (sc == SDL_SCANCODE_UNKNOWN) [rest addObject:press];
        else if (NvDirecao(sc)) NvRemoteTimingRelease(&gTiming, sc);
        else NvBotaoEstado(sc, NO);
    }
    if (!gTiming.direction) { [self.repeatTimer invalidate]; self.repeatTimer = nil; }
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *rest = [NSMutableSet set];
    [self soltar:presses rest:rest];
    if (rest.count) [super pressesEnded:rest withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    NSMutableSet *rest = [NSMutableSet set];
    [self soltar:presses rest:rest];
    if (rest.count) [super pressesCancelled:rest withEvent:event];
}
@end

static NSArray *NvVCPreferido(id self, SEL command) {
    id native = nvui_focus_environment ? (__bridge id)nvui_focus_environment() : nil;
    return native ? @[native] : (gRemote ? @[gRemote] : @[]);
}
static void NvSemToque(id self, SEL command, NSSet *touches, UIEvent *event) {}
typedef void (*NvPressIMP)(id, SEL, NSSet *, UIPressesEvent *);
static NvPressIMP gSDLPress[4], gUIKitPress[4];
static void NvRoutePress(id view, SEL command, NSSet *presses, UIPressesEvent *event, int phase) {
    // Native controls must follow UIKit's normal responder chain for focus.
    // SDL's implementation instead posts raw arrow keys. Use UIView's original
    // implementation while native controls own focus; preserve SDL otherwise.
    NvPressIMP implementation = nvui_owns_focus && nvui_owns_focus() ? gUIKitPress[phase] : gSDLPress[phase];
    if (implementation) implementation(view, command, presses, event);
}
static void NvPressBegan(id v, SEL s, NSSet *p, UIPressesEvent *e) { NvRoutePress(v,s,p,e,0); }
static void NvPressChanged(id v, SEL s, NSSet *p, UIPressesEvent *e) { NvRoutePress(v,s,p,e,1); }
static void NvPressEnded(id v, SEL s, NSSet *p, UIPressesEvent *e) { NvRoutePress(v,s,p,e,2); }
static void NvPressCancelled(id v, SEL s, NSSet *p, UIPressesEvent *e) { NvRoutePress(v,s,p,e,3); }
static void NvDesligarSDL(void) {
    Class view = NSClassFromString(@"SDL_uikitview");
    if (view) {
        SEL selectors[] = {@selector(touchesBegan:withEvent:), @selector(touchesMoved:withEvent:),
                           @selector(touchesEnded:withEvent:), @selector(touchesCancelled:withEvent:)};
        for (unsigned i = 0; i < 4; i++) {
            Method method = class_getInstanceMethod(view, selectors[i]);
            if (method) method_setImplementation(method, (IMP)NvSemToque);
        }
        SEL phases[] = { @selector(pressesBegan:withEvent:), @selector(pressesChanged:withEvent:),
                         @selector(pressesEnded:withEvent:), @selector(pressesCancelled:withEvent:) };
        IMP routes[] = { (IMP)NvPressBegan, (IMP)NvPressChanged, (IMP)NvPressEnded, (IMP)NvPressCancelled };
        for (unsigned i = 0; i < 4; i++) {
            Method method = class_getInstanceMethod(view, phases[i]);
            if (!method) continue;
            gSDLPress[i] = (NvPressIMP)method_getImplementation(method);
            gUIKitPress[i] = (NvPressIMP)class_getMethodImplementation(UIView.class, phases[i]);
            class_replaceMethod(view, phases[i], routes[i], method_getTypeEncoding(method));
        }
    }
    Class controller = NSClassFromString(@"SDL_uikitviewcontroller");
    if (controller) class_replaceMethod(controller, @selector(preferredFocusEnvironments), (IMP)NvVCPreferido, "@@:");
}
static void NvInstalar(void) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
                if ([candidate.rootViewController isKindOfClass:NSClassFromString(@"SDL_uikitviewcontroller")])
                    { window = candidate; break; }
    UIView *view = window.rootViewController.view;
    if (!view || (gRemote && gRemote.superview == view)) return;
    // SDL's built-in swipes must not send a second arrow for the same gesture.
    for (UIGestureRecognizer *gesture in view.gestureRecognizers)
        if ([gesture isKindOfClass:UISwipeGestureRecognizer.class]) gesture.enabled = NO;
    [gRemote cancelarEntrada];
    [gRemote removeFromSuperview];
    gRemote = [[NvRemoteView alloc] initWithFrame:view.bounds];
    [view addSubview:gRemote];
    [window.rootViewController setNeedsFocusUpdate];
    [window.rootViewController updateFocusIfNeeded];
    printf("[remote] direct input installed (4 swipe directions, no focus grid)\n");
}
static int SDLCALL NvVigia(void *unused, SDL_Event *event) {
    if (!gSintetico && event->type == SDL_KEYDOWN) {
        printf("[remote] key outside bridge: %d\n", (int)event->key.keysym.scancode);
    }
    return 0;
}
__attribute__((constructor))
static void nvTVOSRemote(void) {
    setenv("SDL_TV_REMOTE_AS_JOYSTICK", "0", 1);
    setenv("SDL_TOUCH_MOUSE_EVENTS", "0", 1);
    NvDesligarSDL();
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillDeactivateNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *notification) {
        [gRemote cancelarEntrada];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil queue:NSOperationQueue.mainQueue
                                                  usingBlock:^(NSNotification *notification) {
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            static BOOL watching;
            if (!watching && SDL_WasInit(SDL_INIT_VIDEO)) { watching = YES; SDL_AddEventWatch(NvVigia, NULL); }
            NvInstalar();
        }];
    }];
}
