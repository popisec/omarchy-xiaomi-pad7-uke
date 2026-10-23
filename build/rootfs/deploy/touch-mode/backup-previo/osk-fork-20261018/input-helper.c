#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard.h"

/* stdin: <Linux evdev keycode> <modifier bits>\n   |   L <us|es>\n
 * bits: Ctrl=1, Shift=2, Alt=4, Super=8, Caps=16, AltGr=32.
 * UKE FORK: "L us|es" switches the real xkb layout (the virtual keyboard is
 * destroyed and re-created with the new keymap); default layout is es.
 * One real evdev keymap per visible keyboard, not a remapped keymap per tap.
 * Every stroke releases its key and modifiers. No timers, polling, uinput,
 * root permissions, per-key subprocesses, or per-key allocations.
 */
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static void seat_capabilities(void *data, struct wl_seat *s, uint32_t caps) {
    (void)data; (void)s; (void)caps;
}
static void seat_name(void *data, struct wl_seat *s, const char *name) {
    (void)data; (void)s; (void)name;
}
static const struct wl_seat_listener seat_listener = { seat_capabilities, seat_name };
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (!seat && !strcmp(interface, "wl_seat")) {
        seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
        wl_seat_add_listener(seat, &seat_listener, NULL);
    } else if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1")) {
        manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
    }
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = { global, removed };
static uint32_t modifier_mask(struct xkb_keymap *keymap, const char *name) {
    xkb_mod_index_t index = xkb_keymap_mod_get_index(keymap, name);
    return index < 32 ? UINT32_C(1) << index : 0;
}
static uint32_t timestamp(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint32_t)((uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}
struct layout_state {
    uint32_t masks[5];   /* ctrl, shift, alt, logo, altgr (Mod5 = ISO_Level3_Shift) */
    uint32_t caps_mask;
    int fd;
    size_t size;
};
static int build_layout(const char *layout, struct layout_state *st) {
    struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!context) return -1;
    const struct xkb_rule_names rules = { .rules = "evdev", .model = "pc105", .layout = layout };
    struct xkb_keymap *keymap = xkb_keymap_new_from_names(context, &rules, XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_context_unref(context);
    if (!keymap) { fprintf(stderr, "Cannot create %s keymap\n", layout); return -1; }
    st->masks[0] = modifier_mask(keymap, XKB_MOD_NAME_CTRL);
    st->masks[1] = modifier_mask(keymap, XKB_MOD_NAME_SHIFT);
    st->masks[2] = modifier_mask(keymap, XKB_MOD_NAME_ALT);
    st->masks[3] = modifier_mask(keymap, XKB_MOD_NAME_LOGO);
    st->masks[4] = modifier_mask(keymap, "Mod5");
    st->caps_mask = modifier_mask(keymap, XKB_MOD_NAME_CAPS);
    char *text = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
    xkb_keymap_unref(keymap);
    if (!text) return -1;
    size_t size = strlen(text) + 1;
    int fd = memfd_create("omarchy-keyboard-keymap", MFD_CLOEXEC);
    if (fd < 0) { perror("memfd_create"); free(text); return -1; }
    size_t written = 0;
    while (written < size) {
        ssize_t n = write(fd, text + written, size - written);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { perror("keymap write"); free(text); close(fd); return -1; }
        written += (size_t)n;
    }
    free(text);
    st->fd = fd;
    st->size = size;
    return 0;
}
static struct zwp_virtual_keyboard_v1 *make_keyboard(struct wl_display *display, struct layout_state *st) {
    struct zwp_virtual_keyboard_v1 *keyboard =
        zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
    zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, st->fd, (uint32_t)st->size);
    if (wl_display_roundtrip(display) < 0) return NULL;
    return keyboard;
}
int main(void) {
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fputs("Cannot connect to Wayland display\n", stderr); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    if (wl_display_roundtrip(display) < 0 || !seat || !manager) {
        fputs("Compositor does not expose the virtual-keyboard protocol\n", stderr);
        return 1;
    }
    struct layout_state layouts[2];
    const char *names[2] = { "es", "us" };
    for (int i = 0; i < 2; ++i) if (build_layout(names[i], &layouts[i])) return 1;
    int current = 0;
    struct zwp_virtual_keyboard_v1 *keyboard = make_keyboard(display, &layouts[current]);
    if (!keyboard) return 1;
    setvbuf(stdout, NULL, _IOLBF, 0);
    puts("ready");
    char line[64];
    int result = 0;
    while (fgets(line, sizeof(line), stdin)) {
        unsigned code, mods;
        char extra, name[8];
        if (sscanf(line, "L %7s %c", name, &extra) == 1) {
            int want = !strcmp(name, "us") ? 1 : !strcmp(name, "es") ? 0 : -1;
            if (want < 0) { fputs("Unknown layout\n", stderr); result = 1; break; }
            if (want != current) {
                zwp_virtual_keyboard_v1_destroy(keyboard);
                current = want;
                keyboard = make_keyboard(display, &layouts[current]);
                if (!keyboard) { result = 1; break; }
            }
            continue;
        }
        if (sscanf(line, "%u %u %c", &code, &mods, &extra) != 2 || code == 0 || code > 255 || mods > 63) {
            fputs("Invalid keyboard input command\n", stderr); result = 1; break;
        }
        struct layout_state *st = &layouts[current];
        uint32_t depressed = 0;
        for (unsigned i = 0; i < 5; ++i) if (mods & (1u << (i + (i == 4 ? 1 : 0)))) depressed |= st->masks[i];
        zwp_virtual_keyboard_v1_modifiers(keyboard, depressed, 0, mods & 16 ? st->caps_mask : 0, 0);
        uint32_t now = timestamp();
        zwp_virtual_keyboard_v1_key(keyboard, now, code, WL_KEYBOARD_KEY_STATE_PRESSED);
        zwp_virtual_keyboard_v1_key(keyboard, now, code, WL_KEYBOARD_KEY_STATE_RELEASED);
        zwp_virtual_keyboard_v1_modifiers(keyboard, 0, 0, 0, 0);
        if (wl_display_roundtrip(display) < 0) { result = 1; break; }
    }
    zwp_virtual_keyboard_v1_destroy(keyboard);
    wl_proxy_destroy((struct wl_proxy *)manager);
    wl_seat_destroy(seat);
    wl_registry_destroy(registry);
    wl_display_flush(display);
    wl_display_disconnect(display);
    return result;
}
