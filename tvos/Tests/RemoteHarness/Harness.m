// Test-only UIKit host. It compiles the production NvRemote.m unchanged, with
// a counting SDL event sink instead of the media engine or network catalog.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#define SDL_MAIN_HANDLED
#include <SDL2/SDL.h>
#include "../../../legacy/src/nativeui.h"

static unsigned downs[SDL_NUM_SCANCODES], ups[SDL_NUM_SCANCODES];
static UILabel *statusLabel, *focusLabel;
static BOOL keyboardActive;
static BOOL nativeFixture;
static int nativeRow, nativeColumn, nativeFocusUpdates;
static int nativeOffsets[6], nativeTopRow;
static int nativePosterReady;
static int customActivations;
static UIWindow *testWindow;
static void NativeFrame(void);
static SDL_EventFilter eventWatch;
static void *eventWatchData;
static void PresentDialog(void);
extern void nv_test_swift_frame(int selection);
extern int nv_test_swift_readback(void);

static void UpdateStatus(void) {
    NSDictionary *counts = @{
        @"up": @(downs[SDL_SCANCODE_UP]), @"down": @(downs[SDL_SCANCODE_DOWN]),
        @"left": @(downs[SDL_SCANCODE_LEFT]), @"right": @(downs[SDL_SCANCODE_RIGHT]),
        @"select": @(downs[SDL_SCANCODE_RETURN]), @"selectUp": @(ups[SDL_SCANCODE_RETURN]),
        @"menu": @(downs[SDL_SCANCODE_ESCAPE]), @"pause": @(downs[SDL_SCANCODE_PAUSE]),
        @"arrowUps": @(ups[SDL_SCANCODE_UP] + ups[SDL_SCANCODE_DOWN] +
                         ups[SDL_SCANCODE_LEFT] + ups[SDL_SCANCODE_RIGHT]),
        @"row": @(nativeRow), @"column": @(nativeColumn), @"focusUpdates": @(nativeFocusUpdates),
        @"nativePoster": @(nativePosterReady), @"customActivations": @(customActivations), @"nativeReadback": @(nv_test_swift_readback())
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:counts options:NSJSONWritingSortedKeys error:nil];
    NSString *value = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    statusLabel.text = value;
    statusLabel.accessibilityValue = value;
}
BOOL nv_tvos_teclado_ativo(void) { return keyboardActive; }
int nvui_activate(uint64_t identity) {
    if (keyboardActive || !nativeFixture) return 0;
    customActivations++; UpdateStatus(); return 1;
}
int nvui_focus(uint64_t identity) {
    if (!nativeFixture || identity < 1 || keyboardActive) return 0;
    int r = (int)((identity - 1) / 100), c = (int)((identity - 1) % 100);
    if (r >= 6 || c >= 12) return 0;
    nativeRow = r; nativeColumn = c; nativeFocusUpdates++;
    if (c < nativeOffsets[r]) nativeOffsets[r] = c;
    if (c > nativeOffsets[r] + 3) nativeOffsets[r] = c - 3;
    nativeTopRow = r > 2 ? r - 2 : 0;
    UpdateStatus();
    return 1;
}
static void NativeFrame(void) {
    if (!nativeFixture) return;
    NvUIControl controls[72]; int count = 0;
    nvui_frame_begin(1, !keyboardActive);
    static BOOL seeded;
    if (!seeded) {
        seeded = YES;
        unsigned char pixels[64 * 96 * 4];
        for (int y = 0; y < 96; y++) for (int x = 0; x < 64; x++) {
            int i = (y * 64 + x) * 4;
            pixels[i] = y < 48 ? 255 : 0; pixels[i+1] = 0;
            pixels[i+2] = y < 48 ? 0 : 255; pixels[i+3] = y < 48 ? 0 : 255;
        }
        nvui_image_rgba("fixture://poster", pixels, 64, 96, 64 * 4);
    }
    nativePosterReady = nvui_poster(9999, "fixture://poster", 1600, 160, 240, 360, 16, 0, 0, 0);
    for (int r = 0; r < 6; r++) for (int c = 0; c < 12; c++) {
        float x = 248 + (c - nativeOffsets[r]) * 280, y = 160 + (r - nativeTopRow) * 280;
        if (x < 248 || x + 240 > 1480 || y < 100 || y + 230 > 1020) continue;
        controls[count++] = (NvUIControl){(uint64_t)(1 + r * 100 + c), x, y, 240, 230,
            [NSProcessInfo.processInfo.arguments containsObject:@"--custom-action"] ? 1u : 0u};
    }
    BOOL unmarked = [NSProcessInfo.processInfo.arguments containsObject:@"--unmarked-focus"];
    nvui_controls(controls, count, unmarked ? 0 : 1 + nativeRow * 100 + nativeColumn);
    nvui_frame_end();
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--swift-scene"]) nv_test_swift_frame((int)downs[SDL_SCANCODE_RETURN]);
    static BOOL videoInserted;
    if (!videoInserted && [NSProcessInfo.processInfo.arguments containsObject:@"--video-plane"]) {
        videoInserted = YES;
        UIView *canvas = testWindow.rootViewController.view;
        UIView *video = [[UIView alloc] initWithFrame:canvas.superview.bounds];
        video.backgroundColor = UIColor.greenColor;
        video.userInteractionEnabled = NO;
        [canvas.superview insertSubview:video belowSubview:canvas];
    }
    UpdateStatus();
}
void *SDL_memset(void *destination, int value, size_t count) { return memset(destination, value, count); }
Uint32 SDL_GetTicks(void) { return (Uint32)(Uint64)(NSProcessInfo.processInfo.systemUptime * 1000); }
Uint32 SDL_WasInit(Uint32 flags) { return SDL_INIT_VIDEO; }
SDL_Window *SDL_GetKeyboardFocus(void) { return NULL; }
Uint32 SDL_GetWindowID(SDL_Window *window) { return 1; }
SDL_Keycode SDL_GetKeyFromScancode(SDL_Scancode scancode) { return SDL_SCANCODE_TO_KEYCODE(scancode); }
void SDL_AddEventWatch(SDL_EventFilter filter, void *userdata) { eventWatch = filter; eventWatchData = userdata; }
int SDL_PushEvent(SDL_Event *event) {
    if (eventWatch) eventWatch(eventWatchData, event);
    if (event->type == SDL_KEYDOWN) downs[event->key.keysym.scancode]++;
    if (event->type == SDL_KEYUP) ups[event->key.keysym.scancode]++;
    UpdateStatus();
    if (nativeFixture && event->type == SDL_KEYDOWN) {
        switch (event->key.keysym.scancode) {
            case SDL_SCANCODE_UP: nativeRow = MAX(0, nativeRow - 1); break;
            case SDL_SCANCODE_DOWN: nativeRow = MIN(5, nativeRow + 1); break;
            case SDL_SCANCODE_LEFT: nativeColumn = MAX(0, nativeColumn - 1); break;
            case SDL_SCANCODE_RIGHT: nativeColumn = MIN(11, nativeColumn + 1); break;
            default: break;
        }
        if (nativeColumn < nativeOffsets[nativeRow]) nativeOffsets[nativeRow] = nativeColumn;
        if (nativeColumn > nativeOffsets[nativeRow] + 3) nativeOffsets[nativeRow] = nativeColumn - 3;
        nativeTopRow = nativeRow > 2 ? nativeRow - 2 : 0;
        UpdateStatus();
    }
    if (event->type == SDL_KEYUP && event->key.keysym.scancode == SDL_SCANCODE_ESCAPE) PresentDialog();
    return 1;
}

// Model SDL's native parent responder: forwarding a handled arrow here really
// posts another event, exposing the duplicate-input bug in the old bridge.
@interface SDL_uikitview : UIView @end
@implementation SDL_uikitview
+ (Class)layerClass { return CAEAGLLayer.class; }
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {}
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {}
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {}
- (void)postDirections:(NSSet<UIPress *> *)presses down:(BOOL)down {
    for (UIPress *press in presses) {
        SDL_Scancode sc = SDL_SCANCODE_UNKNOWN;
        switch (press.type) {
            case UIPressTypeUpArrow: sc = SDL_SCANCODE_UP; break;
            case UIPressTypeDownArrow: sc = SDL_SCANCODE_DOWN; break;
            case UIPressTypeLeftArrow: sc = SDL_SCANCODE_LEFT; break;
            case UIPressTypeRightArrow: sc = SDL_SCANCODE_RIGHT; break;
            default: continue;
        }
        SDL_Event key = {0}; key.type = down ? SDL_KEYDOWN : SDL_KEYUP; key.key.keysym.scancode = sc;
        SDL_PushEvent(&key);
    }
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self postDirections:presses down:YES];
    if (keyboardActive) [super pressesBegan:presses withEvent:event];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self postDirections:presses down:NO];
    if (keyboardActive) [super pressesEnded:presses withEvent:event];
}
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    [self postDirections:presses down:NO];
    if (keyboardActive) [super pressesCancelled:presses withEvent:event];
}
- (void)pressesChanged:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    if (keyboardActive) [super pressesChanged:presses withEvent:event];
}
@end
@interface SDL_uikitviewcontroller : UIViewController @end
@implementation SDL_uikitviewcontroller
- (void)loadView {
    nativeFixture = [NSProcessInfo.processInfo.arguments containsObject:@"--native-fixture"];
    self.view = [[SDL_uikitview alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.view.backgroundColor = nativeFixture ? UIColor.clearColor : UIColor.blackColor;
    statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(80, 160, 1700, 180)];
    statusLabel.font = [UIFont monospacedSystemFontOfSize:25 weight:UIFontWeightRegular];
    statusLabel.textColor = UIColor.whiteColor;
    statusLabel.numberOfLines = 0;
    statusLabel.accessibilityIdentifier = @"events";
    [self.view addSubview:statusLabel];
    focusLabel = [[UILabel alloc] initWithFrame:CGRectMake(80, 80, 1700, 70)];
    focusLabel.textColor = UIColor.whiteColor;
    focusLabel.accessibilityIdentifier = @"focus-receiver";
    [self.view addSubview:focusLabel];
    UpdateStatus();
    __weak UIViewController *weakSelf = self;
    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        id item = weakSelf.view.window.windowScene.focusSystem.focusedItem;
        focusLabel.text = item ? NSStringFromClass([item class]) : @"none";
        focusLabel.accessibilityValue = focusLabel.text;
    }];
    if (nativeFixture) [NSTimer scheduledTimerWithTimeInterval:1.0/60 repeats:YES block:^(NSTimer *timer) { NativeFrame(); }];
}
@end

static void PresentDialog(void) {
    if (testWindow.rootViewController.presentedViewController) return;
    keyboardActive = YES;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"System dialog"
        message:@"Navigation belongs to the system UI while this is open."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *action) { keyboardActive = NO; }]];
    [testWindow.rootViewController presentViewController:alert animated:NO completion:nil];
}
@interface HarnessScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation HarnessScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = [SDL_uikitviewcontroller new];
    testWindow = self.window;
    [self.window makeKeyAndVisible];
}
@end
@interface HarnessDelegate : UIResponder <UIApplicationDelegate> @end
@implementation HarnessDelegate
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Test" sessionRole:session.role];
    configuration.delegateClass = HarnessScene.class;
    return configuration;
}
@end
int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HarnessDelegate.class)); }
}
