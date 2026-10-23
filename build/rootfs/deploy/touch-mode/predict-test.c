/* pruebas del motor de sugerencias (PC): cc -O2 -Ifork predict-test.c -o /tmp/pt && /tmp/pt fork/dict/es.txt */
#define _GNU_SOURCE
#include <time.h>
#include "predict.h"
static int fails;
static void ac(const char *in, const char *want) {
    char o[PW_MAX]; int r = pred_autocorrect(in, o, sizeof o);
    const char *got = r ? o : "";
    if (strcmp(got, want)) { printf("FALLA autocorrect(%s) = '%s', esperado '%s'\n", in, got, want); fails++; }
}
static void sg(const char *in, const char *first) {
    char o[3][PW_MAX]; int n = pred_suggest(in, o);
    printf("sug %-8s ->", in); for (int i = 0; i < n; i++) printf(" %s", o[i]); printf("\n");
    if (first && (n == 0 || strcmp(o[0], first))) { printf("FALLA sug(%s)[0] != %s\n", in, first); fails++; }
}
int main(int c, char **v) {
    struct timespec a, b; clock_gettime(CLOCK_MONOTONIC, &a);
    int n = pred_load(c > 1 ? v[1] : "fork/dict/es.txt");
    clock_gettime(CLOCK_MONOTONIC, &b);
    printf("cargadas %d palabras en %.1f ms\n", n, (b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6);
    ac("tambien", "también"); ac("cancion", "canción"); ac("aqui", "aquí"); ac("Tambien", "También");
    ac("esta", ""); ac("que", ""); ac("hola", ""); ac("de", ""); ac("hloa", "hola"); ac("graicas", "gracias");
    ac("mañana", ""); ac("manana", "mañana"); ac("TAMBIEN", "TAMBIÉN"); ac("x", ""); ac("abc1", ""); ac("el", "");
    ac("como", ""); ac("porque", ""); ac("telefono", "teléfono"); ac("ano", "año");
    pred_add("Omarchy", 20000); ac("omarchy", ""); { char o3[3][PW_MAX]; int k = pred_suggest("omar", o3); int f = 0; for (int i = 0; i < k; i++) f |= !strcmp(o3[i], "omarchy"); if (!f) { printf("FALLA palabra propia no sugerida\n"); fails++; } }
    sg("tam", "también"); sg("cancion", "canción"); sg("Ma", NULL); sg("graci", "gracias"); sg("qe", NULL); sg("hloa", "hola"); sg("ñ", NULL);
    clock_gettime(CLOCK_MONOTONIC, &a);
    char o[3][PW_MAX]; for (int i = 0; i < 100; i++) pred_suggest("est", o);
    for (int i = 0; i < 100; i++) pred_autocorrect("grasias", o[0], PW_MAX);
    clock_gettime(CLOCK_MONOTONIC, &b);
    printf("200 consultas: %.2f ms por consulta\n", ((b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6) / 200);
    if (c > 2 && !strcmp(v[2], "--swipe")) {           /* lineas "palabra<TAB>trazo" (swipe-paths.py) por stdin */
        char line[1024]; int tot = 0, top1 = 0, top3 = 0;
        clock_gettime(CLOCK_MONOTONIC, &a);
        while (fgets(line, sizeof line, stdin)) {
            char *tab = strchr(line, '\t'); if (!tab) continue;
            *tab = 0; char *pth = tab + 1; pth[strcspn(pth, "\n")] = 0;
            char sw[3][PW_MAX]; int k = pred_swipe(pth, sw), r = -1;
            for (int i = 0; i < k; i++) if (!strcmp(sw[i], line)) { r = i; break; }
            tot++; if (r == 0) top1++; if (r >= 0) top3++;
            printf("swipe %-10s -> %s%s%s %s%s%s %s\n", line, k > 0 ? sw[0] : "-", k > 1 ? " / " : "", k > 1 ? sw[1] : "", k > 2 ? "/ " : "", k > 2 ? sw[2] : "", "", r == 0 ? "OK" : r > 0 ? "(top3)" : "FALLA");
        }
        clock_gettime(CLOCK_MONOTONIC, &b);
        printf("swipe: %d/%d primera, %d/%d entre 3; %.2f ms por trazo\n", top1, tot, top3, tot, ((b.tv_sec - a.tv_sec) * 1e3 + (b.tv_nsec - a.tv_nsec) / 1e6) / (tot ? tot : 1));
        if (top1 * 10 < tot * 7) fails++;                 /* exige >= 70 % a la primera */
    }
    printf(fails ? "RESULTADO: %d FALLOS\n" : "RESULTADO: OK\n", fails);
    return fails != 0;
}
