/*
 * wylde-session-probe — prove a Wayland compositor is not merely alive but
 * actually serving clients.
 *
 * Connects to $WAYLAND_DISPLAY, enumerates the globals the compositor
 * advertises, and prints them. Exits non-zero when it cannot connect, which is
 * what a broken session looks like from the outside.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-client.h>

struct registry_state {
    struct wl_registry *registry;
    int count;
};

static void on_global(void *data, struct wl_registry *registry, uint32_t name,
                      const char *interface, uint32_t version)
{
    struct registry_state *state = data;
    printf("  global %3u  %-28s v%u\n", name, interface, version);
    state->count++;
}

static void on_global_remove(void *data, struct wl_registry *registry, uint32_t name)
{
    (void)data;
    (void)registry;
    (void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = on_global,
    .global_remove = on_global_remove,
};

int main(void)
{
    const char *display = getenv("WAYLAND_DISPLAY");
    if (!display || !*display)
        display = "wayland-0";

    struct wl_display *display_connection = wl_display_connect(display);
    if (!display_connection) {
        fprintf(stderr, "wylde-session-probe: cannot connect to %s\n", display);
        return 1;
    }

    struct registry_state state = { .count = 0 };
    state.registry = wl_display_get_registry(display_connection);
    wl_registry_add_listener(state.registry, &registry_listener, &state);
    wl_display_roundtrip(display_connection);

    /* a second roundtrip: the compositor sends globals asynchronously */
    wl_display_roundtrip(display_connection);

    printf("wylde-session-probe: %s answered with %d globals\n", display, state.count);
    wl_registry_destroy(state.registry);
    wl_display_disconnect(display_connection);
    return state.count > 0 ? 0 : 1;
}