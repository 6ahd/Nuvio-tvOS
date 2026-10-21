// Nuvio Legacy on Apple TV: Continue Watching for the Top Shelf, and the
// dexlegacy://titulo/<imdb> links its items open.
//
// The core hands the row over as text (catalogo.c, topShelfPublicar) from
// whatever thread rebuilt it. It is written to the app group container only
// when it changed, and tvOS is asked to reload the shelf.
#import <Foundation/Foundation.h>
#import <TVServices/TVServices.h>
#include <stdio.h>

void app_abrir_titulo(const char *imdb);   // app.c
int detail_aberto(void);                   // detail.c

static NSString *const kGrupo = @"group.cc.dexworld.dexlegacy";

void nv_tvos_topshelf(const char *texto) {
    NSString *novo = [NSString stringWithUTF8String:texto ? texto : ""] ?: @"";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        static NSString *ultimo;
        @synchronized (kGrupo) {
            if ([ultimo isEqualToString:novo]) return;
            ultimo = novo;
        }
        NSURL *dir = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:kGrupo];
        if (!dir) {
            static BOOL avisou;
            if (!avisou) { avisou = YES; printf("[topshelf] no app group container (signed without it): shelf stays static\n"); fflush(stdout); }
            return;
        }
        dir = [dir URLByAppendingPathComponent:@"TopShelf" isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSError *erro = nil;
        if (![novo writeToURL:[dir URLByAppendingPathComponent:@"continue.txt"] atomically:YES
                     encoding:NSUTF8StringEncoding error:&erro]) {
            printf("[topshelf] write failed: %s\n", erro.localizedDescription.UTF8String); fflush(stdout);
            return;
        }
        [TVTopShelfContentProvider topShelfContentDidChange];
        printf("[topshelf] %lu titles\n", (unsigned long)[novo componentsSeparatedByString:@"\n"].count - 1);
        fflush(stdout);
    });
}

// dexlegacy://titulo/tt1234567 (a Top Shelf item). 1 = handled here.
int nv_tvos_abrir_link(NSURL *url) {
    if (![url.scheme isEqualToString:@"dexlegacy"] || ![url.host isEqualToString:@"titulo"]) return 0;
    NSString *imdb = url.path.lastPathComponent.stringByRemovingPercentEncoding;
    if (imdb.length < 3 || imdb.length > 60) return 1;
    const char *id = strdup(imdb.UTF8String);
    printf("[topshelf] open %s\n", id); fflush(stdout);
    dispatch_async(dispatch_get_main_queue(), ^{ app_abrir_titulo(id); });
    // A cold launch: the core may still be starting and drop the request;
    // ask once more when the home is up, unless the title is already open.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!detail_aberto()) app_abrir_titulo(id);
        free((void *)id);
    });
    return 1;
}
