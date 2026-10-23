#define _GNU_SOURCE
/* UKE OSK daemon (OSK-REWORK-20261020). Un unico proceso persistente que es a la vez:
 *   - input method v2 (zwp_input_method_v2): detecta campos de texto (active/inactive) y escribe texto con
 *     commit_string (acentos y Unicode sin depender de teclas muertas ni del keymap del cliente);
 *   - teclado virtual (zwp_virtual_keyboard_v1) con keymap xkb "es" fijo: teclas especiales, combinaciones
 *     Ctrl/Alt/Super y RESPALDO de texto cuando no hay campo de texto activo (busqueda inversa en el keymap).
 * stdin (una orden por linea):  T <texto utf8> | K <codigo evdev> <bits> | M auto|ime|keys | P | Q
 *   S <n> = aplicar la sugerencia n (0-2) | C 0|1 = autocorreccion off/on   (ESCRITORIO-TACTIL 22-oct-2026)
 *   W [^] <teclas> = palabra deslizada (swipe; '^' = con mayuscula; '*tecla' = esquina del trazo)
 *   bits: Ctrl=1 Shift=2 Alt=4 Super=8 Caps=16 AltGr=32
 * stdout: ready | active | inactive | unavailable | bound | pong | via ime|keys (tras cada T) | err <txt>
 *         sug <a>|<b>|<c> (sugerencias para la palabra en curso; "sug" vacio = ninguna) | caps 0|1 (mayuscula inicial)
 *         fix <orig> <corregida> (autocorreccion aplicada; Retroceso justo despues la deshace)
 * Robustez: flock unico (mata a un huerfano anterior), PDEATHSIG, EOF de stdin = salir, reintento de IM si otro
 * input method ocupa el seat. */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard.h"
#include "input-method.h"
#include "predict.h"

static struct wl_display *display;
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *vk_mgr;
static struct zwp_input_method_manager_v2 *im_mgr;
static struct zwp_virtual_keyboard_v1 *vk;
static struct zwp_input_method_v2 *im;
static int im_pending, im_active = -1, im_serial, im_unavailable;
static time_t im_retry_at;
static enum { M_AUTO, M_IME, M_KEYS } mode = M_AUTO;
static uint32_t mask_ctrl, mask_shift, mask_alt, mask_logo, mask_altgr, mask_caps;
static int hold_ms = 12;
/* prediccion (ESCRITORIO-TACTIL 22-oct-2026): palabra en curso, permisos segun el campo, deshacer autocorreccion */
static char word[PW_MAX]; static char sugs[3][PW_MAX]; static int nsugs; static char last_sug_line[4 * PW_MAX + 8];
static uint32_t ct_hint, ct_purpose, ct_hint_p, ct_purpose_p;
static int autocorrect_on = 1, last_caps = -1;
static uint32_t last_local_ms;
static char undo_orig[PW_MAX], undo_repl[PW_MAX * 2], rejected[PW_MAX];
static char *surr_p; static uint32_t surr_cursor_p; static int surr_seen_p;
/* 2.a ronda: swipe (swipe_last = lo que puso el ultimo trazo, sustituible/borrable entero), espacio automatico tras
 * sugerencia o trazo (la puntuacion lo absorbe), doble espacio = ". ", y palabras propias aprendidas */
static char swipe_last[PW_MAX + 4];
static int auto_space, space_after_word;
static const char *userdict_path;
static char unknown_ring[16][PW_MAX]; static int unknown_pos;

struct sym_loc { uint32_t cp; uint16_t code; uint8_t mods; };
static struct sym_loc *locs; static size_t nlocs;
struct dead_loc { uint32_t sym; uint16_t code; uint8_t mods; };
static struct dead_loc deads[8]; static int ndeads;

static void out(const char *s) { fputs(s, stdout); fputc('\n', stdout); fflush(stdout); }
static uint32_t now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint32_t)((uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000); }

/* ---- registro ---- */
static void seat_caps(void *d, struct wl_seat *s, uint32_t c) { (void)d; (void)s; (void)c; }
static void seat_name(void *d, struct wl_seat *s, const char *n) { (void)d; (void)s; (void)n; }
static const struct wl_seat_listener seat_l = { seat_caps, seat_name };
static void global(void *d, struct wl_registry *r, uint32_t name, const char *i, uint32_t v) {
    (void)d; (void)v;
    if (!seat && !strcmp(i, "wl_seat")) { seat = wl_registry_bind(r, name, &wl_seat_interface, 1); wl_seat_add_listener(seat, &seat_l, NULL); }
    else if (!strcmp(i, "zwp_virtual_keyboard_manager_v1")) vk_mgr = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    else if (!strcmp(i, "zwp_input_method_manager_v2")) im_mgr = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
}
static void removed(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener reg_l = { global, removed };

/* ---- input method ---- */
static void im_activate(void *d, struct zwp_input_method_v2 *m) { (void)d; (void)m; im_pending = 1; }
static void im_deactivate(void *d, struct zwp_input_method_v2 *m) { (void)d; (void)m; im_pending = 0; }
static void im_surr(void *d, struct zwp_input_method_v2 *m, const char *t, uint32_t c, uint32_t a) {
    (void)d; (void)m; (void)a;
    free(surr_p); surr_p = strdup(t ? t : ""); surr_cursor_p = c; surr_seen_p = 1;
}
static void im_cause(void *d, struct zwp_input_method_v2 *m, uint32_t c) { (void)d; (void)m; (void)c; }
static void im_content(void *d, struct zwp_input_method_v2 *m, uint32_t h, uint32_t p) { (void)d; (void)m; ct_hint_p = h; ct_purpose_p = p; }
static void pred_update(void);
static void word_from_surrounding(const char *t, uint32_t cursor);
static void im_done(void *d, struct zwp_input_method_v2 *m) {
    (void)d; (void)m;
    im_serial++;
    ct_hint = ct_hint_p; ct_purpose = ct_purpose_p;
    if (im_pending != im_active) {
        im_active = im_pending; out(im_active ? "active" : "inactive");
        word[0] = 0; undo_orig[0] = 0; rejected[0] = 0; last_caps = -1; swipe_last[0] = 0; auto_space = space_after_word = 0;
    }
    /* texto alrededor (GTK/Qt lo mandan; foot no): solo se confia en el si no hemos escrito en los ultimos 400 ms
     * (si no, puede ir por detras de lo que acabamos de mandar). Recoloca la palabra tras tocar en otro sitio. */
    if (surr_seen_p && im_active == 1 && now_ms() - last_local_ms > 400) word_from_surrounding(surr_p, surr_cursor_p);
    surr_seen_p = 0;
    pred_update();
}
static void im_unavail(void *d, struct zwp_input_method_v2 *m) {
    (void)d; (void)m;
    im_unavailable = 1; im_active = -1; im_pending = 0; im_retry_at = time(NULL) + 3;
    out("unavailable");
}
static const struct zwp_input_method_v2_listener im_l = { im_activate, im_deactivate, im_surr, im_cause, im_content, im_done, im_unavail };
static void bind_im(void) {
    if (!im_mgr) return;
    if (im) { zwp_input_method_v2_destroy(im); im = NULL; }
    im_unavailable = 0; im_serial = 0; im_pending = 0; im_active = -1; ct_hint_p = ct_purpose_p = 0;
    im = zwp_input_method_manager_v2_get_input_method(im_mgr, seat);
    zwp_input_method_v2_add_listener(im, &im_l, NULL);
}

/* ---- keymap / teclado virtual ---- */
static uint32_t modmask(struct xkb_keymap *k, const char *n) { xkb_mod_index_t i = xkb_keymap_mod_get_index(k, n); return i < 32 ? 1u << i : 0; }
static void add_loc(uint32_t cp, int code, int mods) {
    for (size_t i = 0; i < nlocs; i++) if (locs[i].cp == cp) return;   /* se queda la primera (menos modificadores) */
    locs = realloc(locs, (nlocs + 1) * sizeof *locs);
    locs[nlocs++] = (struct sym_loc){ cp, (uint16_t)code, (uint8_t)mods };
}
static int build_keymap(int *fd_out, size_t *size_out) {
    struct xkb_context *c = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!c) return -1;
    struct xkb_rule_names rn = { .rules = "evdev", .model = "pc105", .layout = "es" };
    struct xkb_keymap *k = xkb_keymap_new_from_names(c, &rn, XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_context_unref(c);
    if (!k) return -1;
    mask_ctrl = modmask(k, XKB_MOD_NAME_CTRL); mask_shift = modmask(k, XKB_MOD_NAME_SHIFT);
    mask_alt = modmask(k, XKB_MOD_NAME_ALT); mask_logo = modmask(k, XKB_MOD_NAME_LOGO);
    mask_altgr = modmask(k, "Mod5"); mask_caps = modmask(k, XKB_MOD_NAME_CAPS);
    static const int lvl_mods[4] = { 0, 2, 32, 34 };
    for (int lvl = 0; lvl < 4; lvl++)
        for (int code = 1; code < 249; code++) {
            xkb_keycode_t kc = (xkb_keycode_t)code + 8;
            if (lvl >= (int)xkb_keymap_num_levels_for_key(k, kc, 0)) continue;
            const xkb_keysym_t *syms; int n = xkb_keymap_key_get_syms_by_level(k, kc, 0, lvl, &syms);
            if (n != 1) continue;
            uint32_t cp = xkb_keysym_to_utf32(syms[0]);
            if (cp >= 32 && cp != 127) add_loc(cp, code, lvl_mods[lvl]);
            else if (syms[0] >= XKB_KEY_dead_grave && syms[0] <= XKB_KEY_dead_doublegrave && ndeads < 8 &&
                     (syms[0] == XKB_KEY_dead_acute || syms[0] == XKB_KEY_dead_grave ||
                      syms[0] == XKB_KEY_dead_diaeresis || syms[0] == XKB_KEY_dead_circumflex))
                deads[ndeads++] = (struct dead_loc){ syms[0], (uint16_t)code, (uint8_t)lvl_mods[lvl] };
        }
    char *txt = xkb_keymap_get_as_string(k, XKB_KEYMAP_FORMAT_TEXT_V1);
    xkb_keymap_unref(k);
    if (!txt) return -1;
    size_t size = strlen(txt) + 1;
    int fd = memfd_create("uke-osk-keymap", MFD_CLOEXEC);
    if (fd < 0 || write(fd, txt, size) != (ssize_t)size) { free(txt); return -1; }
    free(txt);
    *fd_out = fd; *size_out = size;
    return 0;
}
static uint32_t mods_to_mask(int bits) {
    uint32_t m = 0;
    if (bits & 1) m |= mask_ctrl;
    if (bits & 2) m |= mask_shift;
    if (bits & 4) m |= mask_alt;
    if (bits & 8) m |= mask_logo;
    if (bits & 32) m |= mask_altgr;
    return m;
}
static void send_key(unsigned code, int bits) {
    zwp_virtual_keyboard_v1_modifiers(vk, mods_to_mask(bits), 0, (bits & 16) ? mask_caps : 0, 0);
    uint32_t t = now_ms();
    zwp_virtual_keyboard_v1_key(vk, t, code, WL_KEYBOARD_KEY_STATE_PRESSED);
    wl_display_flush(display);
    if (hold_ms > 0) usleep((useconds_t)hold_ms * 1000);
    zwp_virtual_keyboard_v1_key(vk, t + (uint32_t)hold_ms + 1, code, WL_KEYBOARD_KEY_STATE_RELEASED);
    zwp_virtual_keyboard_v1_modifiers(vk, 0, 0, 0, 0);
    wl_display_flush(display);
}
/* decodificacion utf8 */
static int next_cp(const char **p, uint32_t *cp) {
    const unsigned char *s = (const unsigned char *)*p;
    if (!*s) return 0;
    int n = s[0] < 0x80 ? 1 : (s[0] >> 5) == 6 ? 2 : (s[0] >> 4) == 14 ? 3 : (s[0] >> 3) == 30 ? 4 : 1;
    uint32_t c = n == 1 ? s[0] : s[0] & (0xff >> (n + 1));
    for (int i = 1; i < n; i++) { if ((s[i] & 0xc0) != 0x80) { n = i; break; } c = (c << 6) | (s[i] & 0x3f); }
    *cp = c; *p += n; return 1;
}
static const struct { uint32_t res, base; uint32_t dead; } decomp[] = {
#define A XKB_KEY_dead_acute
#define G XKB_KEY_dead_grave
#define D XKB_KEY_dead_diaeresis
#define C XKB_KEY_dead_circumflex
 {0xe1,'a',A},{0xe9,'e',A},{0xed,'i',A},{0xf3,'o',A},{0xfa,'u',A},{0xc1,'A',A},{0xc9,'E',A},{0xcd,'I',A},{0xd3,'O',A},{0xda,'U',A},{0xfd,'y',A},{0xdd,'Y',A},
 {0xe0,'a',G},{0xe8,'e',G},{0xec,'i',G},{0xf2,'o',G},{0xf9,'u',G},{0xc0,'A',G},{0xc8,'E',G},{0xcc,'I',G},{0xd2,'O',G},{0xd9,'U',G},
 {0xe4,'a',D},{0xeb,'e',D},{0xef,'i',D},{0xf6,'o',D},{0xfc,'u',D},{0xff,'y',D},{0xc4,'A',D},{0xcb,'E',D},{0xcf,'I',D},{0xd6,'O',D},{0xdc,'U',D},
 {0xe2,'a',C},{0xea,'e',C},{0xee,'i',C},{0xf4,'o',C},{0xfb,'u',C},{0xc2,'A',C},{0xca,'E',C},{0xce,'I',C},{0xd4,'O',C},{0xdb,'U',C},
};
static int key_cp(uint32_t cp) {
    for (size_t i = 0; i < nlocs; i++) if (locs[i].cp == cp) { send_key(locs[i].code, locs[i].mods); return 1; }
    return 0;
}
static int key_decomposed(uint32_t cp) {
    for (size_t i = 0; i < sizeof decomp / sizeof *decomp; i++) if (decomp[i].res == cp)
        for (int d = 0; d < ndeads; d++) if (deads[d].sym == decomp[i].dead) {
            send_key(deads[d].code, deads[d].mods);
            return key_cp(decomp[i].base);
        }
    return 0;
}
/* ---- prediccion ---- */
/* purpose de text-input-v3: 0 normal, 1 alpha, 7 name; hint 0x40 hidden_text, 0x80 sensitive_data, 0x4 auto_capitalization */
static int pred_allowed(void) {
    return npdict && im && !im_unavailable && im_active == 1 && mode != M_KEYS &&
           (ct_purpose == 0 || ct_purpose == 1 || ct_purpose == 7) && !(ct_hint & 0xc0);
}
static int autocorrect_allowed(void) { return autocorrect_on && pred_allowed() && ct_purpose == 0; }
static void word_from_surrounding(const char *t, uint32_t cursor) {
    if (!t) return;
    size_t len = strlen(t); if (cursor > len) cursor = (uint32_t)len;
    size_t st = cursor;                                   /* retrocede sobre letras (utf8) */
    while (st > 0) {
        size_t k = st - 1; while (k > 0 && ((unsigned char)t[k] & 0xc0) == 0x80) k--;
        const char *q = t + k; uint32_t c; p_dec(&q, &c);
        if (!p_isletter(c)) break;
        st = k;
    }
    if (cursor - st < PW_MAX) { memcpy(word, t + st, cursor - st); word[cursor - st] = 0; } else word[0] = 0;
    /* mayuscula inicial: campo vacio o tras . ? ! y espacio, o salto de linea */
    if (ct_hint & 0x4) {
        size_t i = st; int caps = 0;
        if (i == 0) caps = 1;
        else if (t[i - 1] == '\n') caps = 1;
        else if (t[i - 1] == ' ' && i >= 2 && (t[i - 2] == '.' || t[i - 2] == '?' || t[i - 2] == '!')) caps = 1;
        caps = caps && word[0] == 0;
        if (caps != last_caps) { last_caps = caps; out(caps ? "caps 1" : "caps 0"); }
    }
}
static void pred_update(void) {
    char line[sizeof last_sug_line] = "sug";
    nsugs = 0;
    if (pred_allowed() && word[0]) {
        nsugs = pred_suggest(word, sugs);
        size_t n = 3;
        for (int i = 0; i < nsugs; i++) {
            size_t k = strlen(sugs[i]);
            if (n + k + 2 >= sizeof line) break;
            line[n++] = i ? '|' : ' '; memcpy(line + n, sugs[i], k); n += k; line[n] = 0;
        }
    }
    if (strcmp(line, last_sug_line)) { strcpy(last_sug_line, line); out(line); }
}
static void im_replace(size_t del_bytes, const char *text) {
    if (del_bytes) zwp_input_method_v2_delete_surrounding_text(im, (uint32_t)del_bytes, 0);
    if (text && *text) zwp_input_method_v2_commit_string(im, text);
    zwp_input_method_v2_commit(im, (uint32_t)im_serial);
    wl_display_flush(display);
    last_local_ms = now_ms();
}
static void word_pop(void) {
    size_t n = strlen(word);
    while (n > 0) { n--; if (((unsigned char)word[n] & 0xc0) != 0x80) break; }
    word[n] = 0;
}
static void learn(const char *w) {
    if (pred_add(w, 3000) != 2 || !userdict_path) return;          /* 2 = palabra nueva: se guarda */
    FILE *f = fopen(userdict_path, "a");
    if (f) { fprintf(f, "%s\n", w); fclose(f); }
    char msg[PW_MAX + 8]; snprintf(msg, sizeof msg, "learn %s", w); out(msg);
}
/* palabra desconocida terminada: a la 2.a vez se aprende (una errata suelta no) */
static void note_unknown(const char *w) {
    char lo[PW_MAX];
    if (!p_valid_word(w) || p_map(w, lo, PW_MAX, p_lower) < 0 || strlen(lo) < 3 || pred_find(lo)) return;
    for (int i = 0; i < 16; i++) if (!strcmp(unknown_ring[i], lo)) { learn(lo); unknown_ring[i][0] = 0; return; }
    snprintf(unknown_ring[unknown_pos], PW_MAX, "%s", lo); unknown_pos = (unknown_pos + 1) % 16;
}
static void apply_suggestion(int i) {
    if (!pred_allowed() || i < 0 || i >= nsugs) return;
    char t[PW_MAX + 2]; snprintf(t, sizeof t, "%s ", sugs[i]);
    if (swipe_last[0]) { im_replace(strlen(swipe_last), t); snprintf(swipe_last, sizeof swipe_last, "%s", t); }   /* otra lectura del trazo */
    else im_replace(strlen(word), t);
    word[0] = 0; undo_orig[0] = 0; auto_space = 1; space_after_word = 1;
    out("via ime");
    if (!swipe_last[0]) pred_update();
}
static void swipe_word(const char *arg) {
    if (!pred_allowed()) return;
    int cap = 0;
    if (arg[0] == '^' && arg[1] == ' ') { cap = 1; arg += 2; }
    char sw[3][PW_MAX]; int k = pred_swipe(arg, sw);
    if (k <= 0) { out("sug"); last_sug_line[0] = 0; return; }
    for (int i = 0; i < k; i++) { char tmp[PW_MAX]; p_case(cap ? "Xx" : "x", sw[i], tmp, sizeof tmp); snprintf(sugs[i], PW_MAX, "%s", tmp); }
    nsugs = k;
    /* si lo anterior es una palabra pegada (escrita a mano sin espacio), separa con un espacio */
    char t[PW_MAX + 3]; snprintf(t, sizeof t, "%s%s ", (word[0] && !auto_space) ? " " : "", sugs[0]);
    im_replace(0, t);
    snprintf(swipe_last, sizeof swipe_last, "%s", t);
    word[0] = 0; undo_orig[0] = 0; auto_space = 1; space_after_word = 1;
    char line[sizeof last_sug_line] = "sug"; size_t n = 3;           /* las alternativas quedan como sugerencias */
    for (int i = 0; i < nsugs; i++) { size_t l = strlen(sugs[i]); if (n + l + 2 >= sizeof line) break; line[n++] = i ? '|' : ' '; memcpy(line + n, sugs[i], l); n += l; line[n] = 0; }
    strcpy(last_sug_line, line); out(line);
    out("via ime");
}
/* Retroceso: si lo ultimo fue una autocorreccion, la deshace (vuelve lo escrito, sin el espacio) y la recuerda */
static int undo_autocorrect(void) {
    if (!undo_orig[0] || !pred_allowed()) return 0;
    im_replace(strlen(undo_repl), undo_orig);
    snprintf(rejected, sizeof rejected, "%s", undo_orig);
    learn(undo_orig);                                              /* la quiso asi: palabra propia */
    snprintf(word, sizeof word, "%s", undo_orig);
    undo_orig[0] = 0;
    pred_update();
    return 1;
}
static void type_text(const char *text) {
    int use_im = im && !im_unavailable && im_active == 1 && mode != M_KEYS;
    if (mode == M_IME && im && !im_unavailable) use_im = 1;
    if (use_im) {
        const char *q = text; uint32_t cp = 0; int single = p_dec(&q, &cp) && !*q;
        undo_orig[0] = 0;
        if (single && pred_allowed()) {
            int was_auto = auto_space, was_word_space = space_after_word;
            auto_space = 0; space_after_word = 0; swipe_last[0] = 0;
            if (p_isletter(cp)) {                                  /* letra: sigue la palabra */
                size_t n = strlen(word), k = strlen(text);
                if (n + k < PW_MAX) { memcpy(word + n, text, k + 1); }
            } else if (cp == ' ' && was_word_space && !word[0]) {  /* doble espacio tras una palabra = ". " */
                im_replace(1, ". ");
                out("via ime"); out("caps 1"); last_caps = 1;
                pred_update();
                return;
            } else if (was_auto && !word[0] && strchr(".,;:!?)", (int)cp)) {   /* puntuacion tras espacio automatico: lo absorbe */
                char t[8]; snprintf(t, sizeof t, "%.4s ", text);
                im_replace(1, t);
                out("via ime");
                if (cp == '.' || cp == '?' || cp == '!') { out("caps 1"); last_caps = 1; }
                pred_update();
                return;
            } else {                                               /* fin de palabra: autocorreccion */
                if (word[0]) note_unknown(word);
                char fix[PW_MAX];
                if (word[0] && autocorrect_allowed() && strcmp(word, rejected) && pred_autocorrect(word, fix, sizeof fix)) {
                    snprintf(undo_repl, sizeof undo_repl, "%.47s%.4s", fix, text);
                    im_replace(strlen(word), undo_repl);
                    snprintf(undo_orig, sizeof undo_orig, "%s", word);
                    char msg[3 * PW_MAX]; snprintf(msg, sizeof msg, "fix %s %s", word, fix); out(msg);
                    word[0] = 0; rejected[0] = 0; space_after_word = cp == ' ';
                    out("via ime");
                    pred_update();
                    return;
                }
                space_after_word = cp == ' ' && word[0];
                word[0] = 0; rejected[0] = 0;
            }
        } else word[0] = 0;                                         /* dictado / texto largo: sin tocar */
        zwp_input_method_v2_commit_string(im, text);
        zwp_input_method_v2_commit(im, (uint32_t)im_serial);
        wl_display_flush(display);
        last_local_ms = now_ms();
        out("via ime");
        pred_update();
        return;
    }
    const char *p = text; uint32_t cp;
    while (next_cp(&p, &cp)) if (!key_cp(cp) && !key_decomposed(cp)) out("err sin tecla para el caracter");
    out("via keys");
}

/* ---- arranque ---- */
static void lock_single(void) {
    const char *rt = getenv("XDG_RUNTIME_DIR");
    char path[256]; snprintf(path, sizeof path, "%s/uke-osk-daemon.lock", rt ? rt : "/tmp");
    int fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    if (fd < 0) return;
    for (int tries = 0; tries < 20; tries++) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) {
            char b[32]; int n = snprintf(b, sizeof b, "%d\n", (int)getpid());
            if (ftruncate(fd, 0) == 0 && write(fd, b, (size_t)n) < 0) {}
            return;
        }
        char b[32] = {0}; ssize_t n = pread(fd, b, sizeof b - 1, 0);
        int pid = n > 0 ? atoi(b) : 0;
        if (pid > 1 && pid != getpid()) kill(pid, SIGTERM);
        usleep(150000);
    }
}
static void on_term(int s) { (void)s; _exit(0); }

int main(void) {
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    signal(SIGTERM, on_term); signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (getenv("OSK_HOLD_MS")) hold_ms = atoi(getenv("OSK_HOLD_MS"));
    if (getenv("OSK_DICT") && pred_load(getenv("OSK_DICT")) < 0) fputs("sin diccionario: sin sugerencias\n", stderr);
    userdict_path = getenv("OSK_USERDICT");
    if (userdict_path && npdict) {                                 /* palabras propias aprendidas */
        FILE *f = fopen(userdict_path, "r"); char l[PW_MAX + 2];
        while (f && fgets(l, sizeof l, f)) { l[strcspn(l, "\n")] = 0; pred_add(l, 3000); }
        if (f) fclose(f);
    }
    lock_single();
    display = wl_display_connect(NULL);
    if (!display) { fputs("no hay display Wayland\n", stderr); return 1; }
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &reg_l, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !vk_mgr) { fputs("falta virtual-keyboard\n", stderr); return 1; }
    int fd; size_t size;
    if (build_keymap(&fd, &size)) { fputs("keymap es no compila\n", stderr); return 1; }
    vk = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(vk_mgr, seat);
    zwp_virtual_keyboard_v1_keymap(vk, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)size);
    bind_im();
    if (wl_display_roundtrip(display) < 0) return 1;
    out("ready"); out(im_mgr ? "bound" : "unavailable");
    char buf[8192]; size_t blen = 0;
    int stdin_open = 1;
    for (;;) {
        while (wl_display_prepare_read(display) != 0) wl_display_dispatch_pending(display);
        if (wl_display_flush(display) < 0 && errno != EAGAIN) { wl_display_cancel_read(display); return 1; }
        struct pollfd pf[2] = { { wl_display_get_fd(display), POLLIN, 0 }, { 0, POLLIN, 0 } };
        int timeout = (im_unavailable && im_mgr) ? 1000 : -1;
        int r = poll(pf, stdin_open ? 2 : 1, timeout);
        if (r < 0 && errno != EINTR) { wl_display_cancel_read(display); return 1; }
        if (r > 0 && (pf[0].revents & (POLLIN | POLLERR | POLLHUP))) {
            if (wl_display_read_events(display) < 0) return 1;
        } else wl_display_cancel_read(display);
        if (wl_display_dispatch_pending(display) < 0) return 1;
        if (im_unavailable && im_mgr && time(NULL) >= im_retry_at) bind_im();
        if (r > 0 && stdin_open && (pf[1].revents & (POLLIN | POLLHUP))) {
            ssize_t n = read(0, buf + blen, sizeof buf - 1 - blen);
            if (n <= 0) return 0;                      /* el padre murio o cerro stdin */
            blen += (size_t)n; buf[blen] = 0;
            char *nl;
            while ((nl = memchr(buf, '\n', blen))) {
                *nl = 0;
                unsigned code, bits; char word[8];
                if (buf[0] == 'T' && buf[1] == ' ') type_text(buf + 2);
                else if (sscanf(buf, "K %u %u", &code, &bits) == 2 && code > 0 && code < 249 && bits < 64) {
                    if (code == 14 && bits == 0 && undo_autocorrect()) {}
                    else if (code == 14 && bits == 0 && swipe_last[0] && pred_allowed()) {   /* Retroceso tras un trazo: borra la palabra entera */
                        im_replace(strlen(swipe_last), "");
                        swipe_last[0] = 0; auto_space = 0; space_after_word = 0; out("sug"); last_sug_line[0] = 0;
                    }
                    else {
                        send_key(code, (int)bits);
                        undo_orig[0] = 0; swipe_last[0] = 0; auto_space = 0; space_after_word = 0;
                        if (code == 14 && bits == 0) word_pop(); else word[0] = 0;
                        last_local_ms = now_ms();
                        pred_update();
                    }
                }
                else if (sscanf(buf, "S %u", &code) == 1) apply_suggestion((int)code);
                else if (buf[0] == 'W' && buf[1] == ' ') swipe_word(buf + 2);
                else if (sscanf(buf, "C %u", &code) == 1) autocorrect_on = code != 0;
                else if (sscanf(buf, "M %7s", word) == 1) mode = !strcmp(word, "ime") ? M_IME : !strcmp(word, "keys") ? M_KEYS : M_AUTO;
                else if (buf[0] == 'P') out("pong");
                else if (buf[0] == 'Q') return 0;
                else out("err orden desconocida");
                size_t rest = blen - (size_t)(nl - buf) - 1;
                memmove(buf, nl + 1, rest); blen = rest;
            }
            if (blen >= sizeof buf - 1) blen = 0;
        } else if (stdin_open && (pf[1].revents & (POLLERR | POLLNVAL))) return 0;
    }
}
