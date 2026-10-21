#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../legacy/src/artetamanho.h"
int main(void) {
    char url[512];
    const char *poster = "https://image.tmdb.org/t/p/w342/example.jpg?language=ar";
    assert(arte_tamanho_url(poster, 480, url, sizeof url));
    assert(!strcmp(url, "https://image.tmdb.org/t/p/w500/example.jpg?language=ar"));
    assert(arte_tamanho_url(poster, 640, url, sizeof url));
    assert(strstr(url, "/w780/") != NULL);
    assert(arte_tamanho_url(poster, 1200, url, sizeof url));
    assert(strstr(url, "/original/") != NULL);
    assert(!arte_tamanho_url(poster, 300, url, sizeof url));
    assert(!arte_tamanho_url("https://image.tmdb.org.evil/t/p/w342/example.jpg", 640, url, sizeof url));
    assert(!arte_tamanho_url("https://cdn.example/poster.jpg?signature=keep", 640, url, sizeof url));
    assert(!arte_tamanho_url(poster, 640, url, 10));
    assert(arte_tamanho_url("https://image.tmdb.org/t/p/original/backdrop.jpg", 400, url, sizeof url));
    assert(strstr(url, "/w780/") != NULL);
    puts("artwork sizes: PASS (4K promotion, bounds, host identity and signed URLs)");
}
