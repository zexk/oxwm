const std = @import("std");
const xlib = @import("../x11/xlib.zig");
const client_mod = @import("../client.zig");
const Monitor = @import("../monitor.zig").Monitor;
const tiling = @import("../layouts/tiling.zig");
const core = @import("core.zig");
const actions = @import("actions.zig");
const WindowManager = @import("wm.zig").WindowManager;

extern "c" fn getenv(name: [*:0]const u8) ?[*:0]const u8;

// Run against a private X server: OXWM_TEST_DISPLAY=:99 zig build test
test "fullscreen transfer, exclusivity, focus and saved geometry" {
    const display_name = getenv("OXWM_TEST_DISPLAY") orelse return error.SkipZigTest;
    const display = xlib.XOpenDisplay(display_name) orelse return error.CannotOpenDisplay;
    defer _ = xlib.XCloseDisplay(display);
    const root = xlib.XRootWindow(display, xlib.XDefaultScreen(display));
    tiling.setDisplay(display);
    defer tiling.display_handle = null;
    tiling.setScreenSize(1600, 900);

    var source = Monitor{ .mon_w = 800, .mon_h = 600, .win_w = 800, .win_h = 600 };
    var target = Monitor{ .mon_x = 800, .mon_w = 800, .mon_h = 900, .win_x = 800, .win_w = 800, .win_h = 900 };
    source.next = &target;
    var clients: [4]client_mod.Client = undefined;
    for (&clients, 0..) |*client, i| {
        const monitor = if (i == 0) &source else &target;
        client.* = .{
            .window = xlib.c.XCreateSimpleWindow(display, root, monitor.mon_x + 30, 40, 300, 200, 2, 0, 0),
            .monitor = monitor,
            .tags = if (i == 3) 2 else 1,
            .x = monitor.mon_x + 30,
            .y = 40,
            .width = 300,
            .height = 200,
            .border_width = 2,
            .is_floating = true,
        };
        _ = xlib.XMapWindow(display, client.window);
        client_mod.attach(client);
        client_mod.attachStack(client);
    }
    defer for (clients) |client| {
        _ = xlib.XDestroyWindow(display, client.window);
    };
    source.sel = &clients[0];
    target.sel = &clients[1];

    // Only fields used by these operations; no WM startup or desktop takeover.
    var wm: WindowManager = undefined;
    wm.display = .{ .handle = display, .root = root, .screen = xlib.XDefaultScreen(display) };
    wm.config = @import("../config/config.zig").Config.init(std.testing.allocator);
    defer wm.config.deinit();
    wm.bars = null;
    wm.monitors = &source;
    wm.selected_monitor = &source;
    const atoms = @import("../x11/atoms.zig").Atoms.init(display, root);
    wm.atoms = atoms.atoms;
    defer _ = xlib.XDestroyWindow(display, atoms.check_window);

    core.setFullscreen(&clients[0], true, &wm);
    core.setFullscreen(&clients[1], true, &wm);
    core.setFullscreen(&clients[3], true, &wm);
    actions.sendmon(1, &wm);
    try std.testing.expect(clients[0].monitor == &target);
    try std.testing.expect(clients[0].is_fullscreen);
    try std.testing.expect(!clients[1].is_fullscreen);
    try std.testing.expect(clients[3].is_fullscreen);
    var attrs: xlib.XWindowAttributes = undefined;
    _ = xlib.XGetWindowAttributes(display, clients[0].window, &attrs);
    try std.testing.expectEqual(@as(c_int, 800), attrs.x);
    try std.testing.expectEqual(@as(c_int, 900), attrs.height);
    try std.testing.expectEqual(@as(i32, 830), clients[0].old_x);
    try std.testing.expectEqual(@as(i32, 300), clients[0].old_width);

    // Focusing another client must release the fullscreen window covering it.
    target.bar_win = xlib.c.XCreateSimpleWindow(display, root, 800, 0, 800, 20, 0, 0, 0);
    defer _ = xlib.XDestroyWindow(display, target.bar_win);
    _ = xlib.XMapWindow(display, target.bar_win);
    target.lt[0] = &tiling.layout;
    clients[2].is_floating = false;
    core.focus(&clients[2], &wm);
    try std.testing.expect(!clients[0].is_fullscreen);
    try std.testing.expect(clients[3].is_fullscreen);
    try std.testing.expectEqual(@as(i32, 830), clients[0].x);
    try std.testing.expectEqual(@as(i32, 300), clients[0].width);
    try std.testing.expectEqual(@as(i32, 2), clients[0].border_width);

    core.setFullscreen(&clients[1], true, &wm);
    core.setFullscreen(&clients[2], true, &wm);
    try std.testing.expect(!clients[1].is_fullscreen);
    try std.testing.expect(clients[2].is_fullscreen);
    // Retagging a fullscreen client also displaces an existing fullscreen peer.
    actions.tagClient(2, &wm);
    try std.testing.expect(!clients[3].is_fullscreen);
    core.setFullscreen(&clients[2], false, &wm);
    try std.testing.expect(!clients[2].is_floating);
}
