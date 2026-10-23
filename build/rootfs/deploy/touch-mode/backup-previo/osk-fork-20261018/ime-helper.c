#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <wayland-client.h>
#include "input-method.h"

/* UKE FORK: detector de campos de texto. Se registra como input method (zwp_input_method_v2) y escribe en stdout
 * "active" / "inactive" cuando una app enfoca / suelta un campo de texto (text-input-v3). No escribe texto ni
 * graba el teclado: solo observa activate/deactivate. Solo puede haber un input method por seat (squeekboard
 * debe estar parado); si no, imprime "unavailable" y sale con 2.
 */
static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static int pending, current = -1, unavailable;

static void activate(void *d, struct zwp_input_method_v2 *im) { (void)d; (void)im; pending = 1; }
static void deactivate(void *d, struct zwp_input_method_v2 *im) { (void)d; (void)im; pending = 0; }
static void surrounding(void *d, struct zwp_input_method_v2 *im, const char *t, uint32_t c, uint32_t a) { (void)d; (void)im; (void)t; (void)c; (void)a; }
static void cause(void *d, struct zwp_input_method_v2 *im, uint32_t c) { (void)d; (void)im; (void)c; }
static void content(void *d, struct zwp_input_method_v2 *im, uint32_t h, uint32_t p) { (void)d; (void)im; (void)h; (void)p; }
static void done(void *d, struct zwp_input_method_v2 *im) {
    (void)d; (void)im;
    if (pending != current) {
        current = pending;
        puts(current ? "active" : "inactive");
        fflush(stdout);
    }
}
static void unavail(void *d, struct zwp_input_method_v2 *im) { (void)d; (void)im; unavailable = 1; }
static const struct zwp_input_method_v2_listener im_listener = {
    activate, deactivate, surrounding, cause, content, done, unavail
};
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
    (void)d; (void)v;
    if (!seat && !strcmp(iface, "wl_seat")) seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    else if (!strcmp(iface, "zwp_input_method_manager_v2"))
        manager = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
}
static void removed(void *d, struct wl_registry *r, uint32_t n) { (void)d; (void)r; (void)n; }
static const struct wl_registry_listener reg_listener = { global, removed };

int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fputs("Cannot connect to Wayland display\n", stderr); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &reg_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager) {
        fputs("Compositor does not expose zwp_input_method_manager_v2\n", stderr);
        return 1;
    }
    struct zwp_input_method_v2 *im = zwp_input_method_manager_v2_get_input_method(manager, seat);
    zwp_input_method_v2_add_listener(im, &im_listener, NULL);
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (wl_display_roundtrip(display) < 0) return 1;
    puts("ready");
    while (!unavailable && wl_display_dispatch(display) >= 0) {}
    if (unavailable) { puts("unavailable"); return 2; }
    return 1;
}
