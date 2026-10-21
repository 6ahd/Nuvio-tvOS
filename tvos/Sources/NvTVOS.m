// Nuvio Legacy on Apple TV: process-level glue for the C core.
//
// Runs before SDL_main (constructor) to point the core at writable folders,
// and exposes the small C API declared in legacy/src/tvos.h.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static char gDirDados[1024];
static char gLog[1100];

// --- Mirror of the small state files ------------------------------------------
// tvOS gives apps no permanent Documents folder: Caches survives restarts and
// updates, but the system may purge it under storage pressure. The files that
// matter (account session, settings, profiles, device id) are small, so they
// are mirrored into NSUserDefaults and put back at launch when missing.
static NSString *const kMirrorKey = @"nv.mirror.v1";
static const NSUInteger kMirrorFileMax = 128 * 1024;
static const NSUInteger kMirrorTotalMax = 400 * 1024;   // tvOS keeps defaults small

static NSString *DirDados(void) { return [NSString stringWithUTF8String:gDirDados]; }

static BOOL MirrorSkips(NSString *name) {
    NSString *l = name.lowercaseString;
    if ([l hasPrefix:@"."]) return YES;
    if ([l containsString:@"log"] || [l containsString:@"cache"] || [l containsString:@"tmp"]) return YES;
    if ([l isEqualToString:@"despedida.txt"]) return YES;
    if ([l hasSuffix:@".png"] || [l hasSuffix:@".jpg"] || [l hasSuffix:@".webp"] || [l hasSuffix:@".bin"]) return YES;
    return NO;
}

static NSInteger MirrorRank(NSString *name) {
    NSString *l = name.lowercaseString;
    NSArray<NSString *> *first = @[ @"sess", @"conta", @"token", @"auth", @"cliente", @"ajust", @"perf",
                                    @"trakt", @"simkl", @"addon", @"sync" ];
    for (NSUInteger i = 0; i < first.count; i++)
        if ([l containsString:first[i]]) return (NSInteger)i;
    return 100;
}

static void MirrorRestore(void) {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMirrorKey];
    if (!saved.count) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger restored = 0;
    for (NSString *name in saved) {
        NSData *data = saved[name];
        if (![data isKindOfClass:[NSData class]] || [name containsString:@"/"]) continue;
        NSString *path = [DirDados() stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:path]) continue;
        if ([data writeToFile:path atomically:YES]) restored++;
    }
    if (restored) NSLog(@"[tvos] restored %lu state file(s) from defaults", (unsigned long)restored);
}

static void MirrorSave(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:DirDados() error:&directoryError];
    // A temporary I/O failure must not replace the last good backup with {}.
    if (!names || directoryError) return;
    NSDictionary *previous = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kMirrorKey];
    names = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger ra = MirrorRank(a), rb = MirrorRank(b);
        if (ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        return [a compare:b];
    }];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSUInteger total = 0;
    for (NSString *name in names) {
        if (MirrorSkips(name)) continue;
        NSString *path = [DirDados() stringByAppendingPathComponent:name];
        NSDictionary *attr = [fm attributesOfItemAtPath:path error:nil];
        if (![attr[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
        unsigned long long size = [attr fileSize];
        if (size > kMirrorFileMax || total + size > kMirrorTotalMax) continue;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            id saved = previous[name];
            if ([saved isKindOfClass:NSData.class] && [saved length] <= kMirrorFileMax &&
                total + [saved length] <= kMirrorTotalMax) data = saved;
        }
        if (!data) continue;
        if (data.length > kMirrorFileMax || total + data.length > kMirrorTotalMax) continue;
        out[name] = data;
        total += data.length;
    }
    if (![out isEqualToDictionary:previous])
        [[NSUserDefaults standardUserDefaults] setObject:out forKey:kMirrorKey];
}

// --- Clean-exit marker (dados_despedida_ler) ---------------------------------
// tvOS kills a suspended app without a clean exit, like Android. Without the
// "oculto" marker every return through the Home button would count as a crash
// and the core's safe mode would roll back settings under test.
static void Despedida(BOOL hidden) {
    NSString *path = [DirDados() stringByAppendingPathComponent:@"despedida.txt"];
    if (hidden) [@"oculto\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
}

static NSTimer *gMirrorTimer;

__attribute__((constructor))
static void nvTVOSPrepararAmbiente(void) {
    @autoreleasepool {
        NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *dados = [caches stringByAppendingPathComponent:@"nuvio"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dados withIntermediateDirectories:YES attributes:nil error:nil];
        snprintf(gDirDados, sizeof gDirDados, "%s", dados.fileSystemRepresentation);
        setenv("NUVIO_DADOS", gDirDados, 1);
        setenv("HOME", caches.fileSystemRepresentation, 1);
        NSString *tmp = NSTemporaryDirectory();
        setenv("TMPDIR", tmp.fileSystemRepresentation, 1);
        snprintf(gLog, sizeof gLog, "%s/nuvio.log", gDirDados);
        setenv("NUVIO_LOG", gLog, 0);

        MirrorRestore();

        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil
                    usingBlock:^(NSNotification *n) { Despedida(YES); MirrorSave(); }];
        [nc addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil
                    usingBlock:^(NSNotification *n) { MirrorSave(); }];
        [nc addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil
                    usingBlock:^(NSNotification *n) { Despedida(NO); }];
        [nc addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil
                    usingBlock:^(NSNotification *n) {
            // Logging in or changing a setting should survive a purge even if
            // the app is never backgrounded cleanly.
            gMirrorTimer = [NSTimer scheduledTimerWithTimeInterval:90 repeats:YES
                                                             block:^(NSTimer *t) { MirrorSave(); }];
        }];
    }
}

// --- UIScene lifecycle (tvOS 27+) ---------------------------------------------
// Apps built with the tvOS 27 SDK must adopt UIScene or UIKit traps at launch
// (_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption). SDL2 only
// knows the old app-delegate world: it creates its UIWindow with initWithFrame:
// and never attaches a scene. Info.plist now declares NvSceneDelegate; this
// file hands SDL's windows to the connected scene and forwards the scene
// lifecycle to SDL's app delegate (background/foreground events, open URL).
#import <objc/runtime.h>

static UIWindowScene *gScene;
static NSHashTable<UIWindow *> *gSemCena;   // windows created before the scene

static UIWindowScene *NvCena(void) {
    if (gScene) return gScene;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { gScene = (UIWindowScene *)s; break; }
    return gScene;
}

static void NvAnexar(UIWindow *w) {
    UIWindowScene *s = NvCena();
    if (!w || w.windowScene || !s) return;
    w.windowScene = s;
    w.frame = s.coordinateSpace.bounds;
}

static id (*origInitWithFrame)(id, SEL, CGRect);
static id nvInitWithFrame(UIWindow *self, SEL _cmd, CGRect frame) {
    self = origInitWithFrame(self, _cmd, frame);
    if (self && !self.windowScene) {
        if (NvCena()) NvAnexar(self);
        else {
            if (!gSemCena) gSemCena = [NSHashTable weakObjectsHashTable];
            [gSemCena addObject:self];
        }
    }
    return self;
}

static void (*origMakeKeyAndVisible)(id, SEL);
static void nvMakeKeyAndVisible(UIWindow *self, SEL _cmd) {
    if (!self.windowScene && !NvCena()) {
        // SDL_main can run before the scene connects: let the run loop deliver
        // the connection (bounded), then attach.
        NSDate *ate = [NSDate dateWithTimeIntervalSinceNow:3.0];
        while (!NvCena() && [ate timeIntervalSinceNow] > 0)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
    }
    NvAnexar(self);
    origMakeKeyAndVisible(self, _cmd);
}

__attribute__((constructor))
static void nvTVOSCenas(void) {
    Method m = class_getInstanceMethod(UIWindow.class, @selector(initWithFrame:));
    origInitWithFrame = (void *)method_setImplementation(m, (IMP)nvInitWithFrame);
    m = class_getInstanceMethod(UIWindow.class, @selector(makeKeyAndVisible));
    origMakeKeyAndVisible = (void *)method_setImplementation(m, (IMP)nvMakeKeyAndVisible);
}

int nv_tvos_abrir_link(NSURL *url);   // NvTopShelf.m

@interface NvSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation NvSceneDelegate
- (id<UIApplicationDelegate>)appDelegate { return UIApplication.sharedApplication.delegate; }

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
      options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    gScene = (UIWindowScene *)scene;
    for (UIWindow *w in gSemCena.allObjects) {
        BOOL eraChave = w.isKeyWindow || !w.hidden;
        NvAnexar(w);
        if (eraChave) origMakeKeyAndVisible(w, @selector(makeKeyAndVisible));
    }
    [gSemCena removeAllObjects];
    for (UIOpenURLContext *c in connectionOptions.URLContexts) [self abrir:c.URL];
}
- (void)abrir:(NSURL *)url {
    if (nv_tvos_abrir_link(url)) return;   // NvTopShelf.m: dexlegacy://titulo/<imdb>
    id<UIApplicationDelegate> d = [self appDelegate];
    if ([d respondsToSelector:@selector(application:openURL:options:)])
        [d application:UIApplication.sharedApplication openURL:url options:@{}];
}
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts {
    for (UIOpenURLContext *c in contexts) [self abrir:c.URL];
}
- (void)sceneWillResignActive:(UIScene *)scene {
    id<UIApplicationDelegate> d = [self appDelegate];
    if ([d respondsToSelector:@selector(applicationWillResignActive:)])
        [d applicationWillResignActive:UIApplication.sharedApplication];
}
- (void)sceneDidEnterBackground:(UIScene *)scene {
    id<UIApplicationDelegate> d = [self appDelegate];
    if ([d respondsToSelector:@selector(applicationDidEnterBackground:)])
        [d applicationDidEnterBackground:UIApplication.sharedApplication];
    Despedida(YES);
    MirrorSave();
}
- (void)sceneWillEnterForeground:(UIScene *)scene {
    id<UIApplicationDelegate> d = [self appDelegate];
    if ([d respondsToSelector:@selector(applicationWillEnterForeground:)])
        [d applicationWillEnterForeground:UIApplication.sharedApplication];
    Despedida(NO);
}
- (void)sceneDidBecomeActive:(UIScene *)scene {
    id<UIApplicationDelegate> d = [self appDelegate];
    if ([d respondsToSelector:@selector(applicationDidBecomeActive:)])
        [d applicationDidBecomeActive:UIApplication.sharedApplication];
}
@end

const char *nv_tvos_dir_dados(void) { return gDirDados; }

void nv_tvos_abrir_url(const char *url) {
    if (!url || !*url) return;
    NSString *s = [NSString stringWithUTF8String:url];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *u = [NSURL URLWithString:s];
        if (!u) { NSLog(@"[tvos] URL invalida: %@", s); return; }
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:^(BOOL ok) {
            NSLog(@"[tvos] abrir %@ -> %d", s, ok);
        }];
    });
}

int nv_tvos_system(const char *cmd) {
    NSLog(@"[tvos] system() indisponivel: %s", cmd ? cmd : "");
    return -1;
}
FILE *nv_tvos_popen(const char *cmd, const char *mode) {
    (void)mode;
    NSLog(@"[tvos] popen() indisponivel: %s", cmd ? cmd : "");
    return NULL;
}
int nv_tvos_pclose(FILE *f) { (void)f; return -1; }
