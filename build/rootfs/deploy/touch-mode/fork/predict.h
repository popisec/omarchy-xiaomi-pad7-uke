/* predict.h — sugerencias y autocorreccion en espanol para osk-daemon (ESCRITORIO-TACTIL 22-oct-2026).
 * Diccionario: "palabra frecuencia" por linea (FrequencyWords es_50k, CC-BY-SA 4.0, ver dict/README).
 * Todo en memoria (~1 MB) y busqueda lineal: 50k entradas en < 2 ms en el SM7675, sin indices que mantener.
 * Clave de busqueda = forma "plegada": minusculas sin tildes ni dieresis y n~ -> n, para que "cancion" sugiera
 * "cancion" con tilde y "ano" sugiera "ano" con enye. Se compila tambien en el PC con predict-test.c. */
#ifndef UKE_PREDICT_H
#define UKE_PREDICT_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PW_MAX 48                       /* bytes de una palabra (utf8) */
struct pentry { char w[PW_MAX]; char f[PW_MAX]; uint32_t freq; uint8_t flen; };
static struct pentry *pdict; static size_t npdict;

static uint32_t p_lower(uint32_t c) {
    if (c >= 'A' && c <= 'Z') return c + 32;
    if ((c >= 0xc0 && c <= 0xde && c != 0xd7)) return c + 32;
    return c;
}
static uint32_t p_fold(uint32_t c) {
    c = p_lower(c);
    switch (c) {
    case 0xe1: case 0xe0: case 0xe2: case 0xe4: case 0xe3: return 'a';
    case 0xe9: case 0xe8: case 0xea: case 0xeb: return 'e';
    case 0xed: case 0xec: case 0xee: case 0xef: return 'i';
    case 0xf3: case 0xf2: case 0xf4: case 0xf6: case 0xf5: return 'o';
    case 0xfa: case 0xf9: case 0xfb: case 0xfc: return 'u';
    case 0xf1: return 'n';
    case 0xfd: case 0xff: return 'y';
    }
    return c;
}
static int p_dec(const char **p, uint32_t *cp) {
    const unsigned char *s = (const unsigned char *)*p;
    if (!*s) return 0;
    int n = s[0] < 0x80 ? 1 : (s[0] >> 5) == 6 ? 2 : (s[0] >> 4) == 14 ? 3 : (s[0] >> 3) == 30 ? 4 : 1;
    uint32_t c = n == 1 ? s[0] : s[0] & (0xff >> (n + 1));
    for (int i = 1; i < n; i++) { if ((s[i] & 0xc0) != 0x80) { n = i; break; } c = (c << 6) | (s[i] & 0x3f); }
    *cp = c; *p += n; return 1;
}
static int p_enc(uint32_t c, char *o) {
    if (c < 0x80) { o[0] = (char)c; return 1; }
    if (c < 0x800) { o[0] = (char)(0xc0 | (c >> 6)); o[1] = (char)(0x80 | (c & 0x3f)); return 2; }
    if (c < 0x10000) { o[0] = (char)(0xe0 | (c >> 12)); o[1] = (char)(0x80 | ((c >> 6) & 0x3f)); o[2] = (char)(0x80 | (c & 0x3f)); return 3; }
    o[0] = (char)(0xf0 | (c >> 18)); o[1] = (char)(0x80 | ((c >> 12) & 0x3f)); o[2] = (char)(0x80 | ((c >> 6) & 0x3f)); o[3] = (char)(0x80 | (c & 0x3f)); return 4;
}
/* transforma s con fn (p_lower o p_fold) a out; devuelve longitud en bytes o -1 si no cabe */
static int p_map(const char *s, char *out, size_t cap, uint32_t (*fn)(uint32_t)) {
    size_t n = 0; uint32_t c;
    while (p_dec(&s, &c)) { char b[4]; int k = p_enc(fn(c), b); if (n + (size_t)k >= cap) return -1; memcpy(out + n, b, (size_t)k); n += (size_t)k; }
    out[n] = 0; return (int)n;
}
/* letra de palabra: latinas basicas y latin-1 con tilde/enye/cedilla */
static int p_isletter(uint32_t c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= 0xc0 && c <= 0xff && c != 0xd7 && c != 0xf7);
}
static int p_valid_word(const char *s) {
    uint32_t c; int n = 0;
    while (p_dec(&s, &c)) { if (!p_isletter(c)) return 0; n++; }
    return n > 0;
}
static int pred_load(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char line[256]; size_t cap = 0;
    while (fgets(line, sizeof line, f)) {
        char *sp = strchr(line, ' ');
        if (!sp) continue;
        *sp = 0;
        if (!p_valid_word(line) || strlen(line) >= PW_MAX) continue;
        if (npdict == cap) { cap = cap ? cap * 2 : 4096; pdict = realloc(pdict, cap * sizeof *pdict); if (!pdict) { fclose(f); return -1; } }
        struct pentry *e = &pdict[npdict];
        if (p_map(line, e->w, PW_MAX, p_lower) < 0) continue;
        int fl = p_map(line, e->f, PW_MAX, p_fold);
        if (fl < 0) continue;
        e->flen = (uint8_t)fl; e->freq = (uint32_t)strtoul(sp + 1, NULL, 10);
        /* duplicados en minusculas ("Madrid"/"madrid"): se suma la frecuencia */
        int dup = 0;
        for (size_t i = npdict > 64 ? npdict - 64 : 0; i < npdict; i++) if (!strcmp(pdict[i].w, e->w)) { pdict[i].freq += e->freq; dup = 1; break; }
        if (!dup) npdict++;
    }
    fclose(f);
    return (int)npdict;
}
static const struct pentry *pred_find(const char *lower) {
    for (size_t i = 0; i < npdict; i++) if (!strcmp(pdict[i].w, lower)) return &pdict[i];
    return NULL;
}
/* Damerau-Levenshtein <= 1 entre dos cadenas utf8 plegadas (por puntos de codigo) */
static int p_cps(const char *s, uint32_t *o, int cap) { int n = 0; uint32_t c; while (n < cap && p_dec(&s, &c)) o[n++] = c; return n; }
static int p_dist1(const char *a, const char *b) {
    uint32_t x[PW_MAX], y[PW_MAX]; int n = p_cps(a, x, PW_MAX), m = p_cps(b, y, PW_MAX);
    if (abs(n - m) > 1) return 0;
    int i = 0; while (i < n && i < m && x[i] == y[i]) i++;
    if (i == n && i == m) return 0;                                  /* iguales: no es "distancia 1" */
    if (n == m) {
        if (!memcmp(x + i + 1, y + i + 1, (size_t)(n - i - 1) * 4)) return 1;                       /* sustitucion */
        if (i + 1 < n && x[i] == y[i + 1] && x[i + 1] == y[i] && !memcmp(x + i + 2, y + i + 2, (size_t)(n - i - 2) * 4)) return 1;  /* transposicion */
        return 0;
    }
    if (n > m) return !memcmp(x + i + 1, y + i, (size_t)(m - i) * 4);   /* borrado */
    return !memcmp(x + i, y + i + 1, (size_t)(n - i) * 4);               /* insercion */
}
/* Aplica las mayusculas de lo escrito (Inicial o TODO) a la sugerencia. */
static void p_case(const char *typed, const char *w, char *out, size_t cap) {
    uint32_t c; const char *t = typed; int n = 0, up = 0, first_up = 0;
    while (p_dec(&t, &c)) { if (p_lower(c) != c) { up++; if (n == 0) first_up = 1; } n++; }
    int all = n > 1 && up == n;
    size_t o = 0; int i = 0; const char *s = w;
    while (p_dec(&s, &c)) {
        uint32_t u = c;
        if (all || (first_up && i == 0)) { if (c >= 'a' && c <= 'z') u = c - 32; else if (c >= 0xe0 && c <= 0xfe && c != 0xf7) u = c - 32; }
        char b[4]; int k = p_enc(u, b); if (o + (size_t)k >= cap) break; memcpy(out + o, b, (size_t)k); o += (size_t)k; i++;
    }
    out[o] = 0;
}

/* Hasta 3 sugerencias para la palabra a medias "typed". Devuelve cuantas. */
static int pred_suggest(const char *typed, char out[3][PW_MAX]) {
    char lo[PW_MAX], fo[PW_MAX];
    if (!npdict || !*typed || p_map(typed, lo, PW_MAX, p_lower) < 0) return 0;
    int fl = p_map(typed, fo, PW_MAX, p_fold);
    if (fl < 0) return 0;
    const struct pentry *best[3] = {0}; double bs[3] = {0};
    int ncp = 0; { const char *t = typed; uint32_t c; while (p_dec(&t, &c)) ncp++; }
    int marked = strcmp(lo, fo) != 0;
    for (size_t i = 0; i < npdict; i++) {
        const struct pentry *e = &pdict[i];
        double s = 0;
        if (e->flen >= fl && !memcmp(e->f, fo, (size_t)fl)) {
            s = e->freq;
            if (e->flen == fl) s *= 4;                   /* palabra completa (con o sin tilde) primero */
            if (!strcmp(e->w, lo)) s *= 2;               /* lo escrito tal cual, si existe */
            else if (marked && strncmp(e->w, lo, strlen(lo))) s = 0;      /* si ya escribio tilde/enye, se respeta */
        } else if (ncp >= 3 && p_dist1(e->f, fo)) s = e->freq * 0.08;   /* correccion de una letra */
        if (s <= 0) continue;
        for (int k = 0; k < 3; k++) if (s > bs[k]) {
            for (int j = 2; j > k; j--) { bs[j] = bs[j - 1]; best[j] = best[j - 1]; }
            bs[k] = s; best[k] = e; break;
        }
    }
    int n = 0;
    (void)bs;
    for (int k = 0; k < 3 && best[k]; k++) p_case(typed, best[k]->w, out[n++], PW_MAX);
    return n;
}
/* Correccion automatica al cerrar la palabra (espacio/puntuacion). NULL = no tocar.
 * Conservadora: (1) tildes que faltan cuando la forma con tilde es >= 10x mas frecuente ("tambien", "cancion");
 * (2) palabra inexistente de >= 4 letras con un unico candidato claro a una letra de distancia ("qeu" no, "hloa" si). */
static int pred_autocorrect(const char *typed, char *out, size_t cap) {
    char lo[PW_MAX], fo[PW_MAX];
    if (!npdict || !p_valid_word(typed) || p_map(typed, lo, PW_MAX, p_lower) < 0) return 0;
    int fl = p_map(typed, fo, PW_MAX, p_fold);
    int ncp = 0; { const char *t = typed; uint32_t c; while (p_dec(&t, &c)) ncp++; }
    if (fl < 0 || ncp < 2) return 0;
    const struct pentry *self = pred_find(lo), *acc = NULL, *d1 = NULL, *d1b = NULL;
    for (size_t i = 0; i < npdict; i++) {
        const struct pentry *e = &pdict[i];
        if (e == self) continue;
        if (e->flen == fl && !strcmp(e->f, fo)) { if (!acc || e->freq > acc->freq) acc = e; }
        else if (!self && ncp >= 4 && p_dist1(e->f, fo)) {
            if (!d1 || e->freq > d1->freq) { d1b = d1; d1 = e; } else if (!d1b || e->freq > d1b->freq) d1b = e;
        }
    }
    const struct pentry *r = NULL;
    if (acc && (!self || acc->freq >= 10u * self->freq)) r = acc;
    else if (!self && d1 && d1->freq >= 2000 && (!d1b || d1->freq >= 4u * d1b->freq)) r = d1;
    if (!r) return 0;
    p_case(typed, r->w, out, cap);
    return strcmp(out, typed) != 0;
}

/* ---- palabras propias (ESCRITORIO-TACTIL 22-oct-2026, 2.a ronda) ----
 * Se anaden en memoria (y el demonio las guarda en ~/.local/state/uke-touch-mode/palabras.txt): las que el usuario
 * rechaza al deshacer una correccion y las desconocidas que escribe dos veces. Asi dejan de corregirse y se sugieren. */
static int pred_add(const char *word, uint32_t freq) {
    char lo[PW_MAX];
    if (!p_valid_word(word) || p_map(word, lo, PW_MAX, p_lower) < 0) return 0;
    for (size_t i = 0; i < npdict; i++) if (!strcmp(pdict[i].w, lo)) { if (pdict[i].freq < freq) pdict[i].freq = freq; return 1; }
    struct pentry *n = realloc(pdict, (npdict + 1) * sizeof *pdict);
    if (!n) return 0;
    pdict = n;
    struct pentry *e = &pdict[npdict];
    memcpy(e->w, lo, strlen(lo) + 1);
    int fl = p_map(lo, e->f, PW_MAX, p_fold);
    if (fl < 0) return 0;
    e->flen = (uint8_t)fl; e->freq = freq;
    npdict++;
    return 2;
}

/* ---- escritura deslizando (swipe), version ligera ----
 * El teclado manda las teclas que cruza el dedo, en orden, separadas por espacios; un '*' delante marca las
 * obligatorias (primera, ultima y esquinas del trazo, donde el dedo cambia de direccion). Una palabra encaja si sus
 * letras (plegadas) aparecen en ese orden en el trazo sin saltarse ninguna obligatoria, empieza en la primera tecla y
 * acaba en la ultima. Las letras dobles usan la misma tecla. Se ordena por frecuencia. Sin modelo ni datos extra. */
#define SW_MAX 96
#define SW_KEEP 8
/* strict=1: no se puede saltar ninguna esquina; strict=0: solo cuentan primera y ultima (respaldo si un temblor del dedo
 * marco una esquina falsa y nada encaja). */
static int p_swipe_pass(const uint32_t *P, const int *R0, int n, int strict, const struct pentry **best, double *bs) {
    int R[SW_MAX];
    for (int q = 0; q < n; q++) R[q] = strict ? R0[q] : (q == 0 || q == n - 1);
    int found = 0;
    for (size_t i = 0; i < npdict; i++) {
        const struct pentry *e = &pdict[i];
        uint32_t W[PW_MAX]; int m = p_cps(e->f, W, PW_MAX);
        if (m < 2 || W[0] != P[0] || W[m - 1] != P[n - 1]) continue;
        int j = 0, ok = 1, used = 0, lastj = 0;
        for (int k = 1; k < m - 1 && ok; k++) {                    /* letras intermedias, en orden, en P[0..n-2] */
            while (j < n - 1 && P[j] != W[k]) { if (R[j] && j > 0 && P[j] != W[k - 1]) { ok = 0; break; } j++; }
            if (j >= n - 1) ok = 0;
            else if (j != lastj) { used += R0[j]; lastj = j; }      /* esquinas del trazo que la palabra si usa */
        }
        if (!ok) continue;
        for (int q = j + 1; q < n - 1; q++) if (R[q]) { ok = 0; break; }   /* esquinas sin usar antes del final */
        if (!ok) continue;
        found++;
        double sc = (double)e->freq * (1.0 + 0.15 * m);           /* a igual encaje, algo mas a las largas */
        if (!strict) sc *= (1.0 + used) * (1.0 + used) * (1.0 + used);   /* respaldo: premia usar las esquinas */
        for (int k = 0; k < SW_KEEP; k++) if (sc > bs[k]) {
            for (int z = SW_KEEP - 1; z > k; z--) { bs[z] = bs[z - 1]; best[z] = best[z - 1]; }
            bs[k] = sc; best[k] = e; break;
        }
    }
    return found;
}
static int pred_swipe(const char *path, char out[3][PW_MAX]) {
    uint32_t P[SW_MAX]; int R[SW_MAX]; int n = 0;
    const char *s = path;
    while (*s && n < SW_MAX) {
        while (*s == ' ') s++;
        if (!*s) break;
        int req = 0;
        if (*s == '*') { req = 1; s++; }
        uint32_t c;
        if (!p_dec(&s, &c)) break;
        c = p_fold(c);
        while (*s && *s != ' ') s++;
        if (n > 0 && P[n - 1] == c) { R[n - 1] |= req; continue; }    /* misma tecla seguida: una sola */
        P[n] = c; R[n] = req; n++;
    }
    if (n < 2) return 0;
    R[0] = R[n - 1] = 1;
    const struct pentry *best[SW_KEEP] = {0}; double bs[SW_KEEP] = {0};
    if (!p_swipe_pass(P, R, n, 1, best, bs)) p_swipe_pass(P, R, n, 0, best, bs);
    /* variantes con la misma forma plegada (que/qué) solo si son frecuentes: fuera erratas del corpus (tambíen, què) */
    int c = 0;
    for (int k = 0; k < SW_KEEP && best[k] && c < 3; k++) {
        int dup = 0;
        for (int z = 0; z < k; z++) if (best[z] && !strcmp(best[z]->f, best[k]->f) && best[k]->freq * 50u < best[z]->freq) dup = 1;
        if (dup) continue;
        memcpy(out[c], best[k]->w, strlen(best[k]->w) + 1); c++;
    }
    return c;
}
#endif
