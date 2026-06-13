const std = @import("std");
const client_mod = @import("../client.zig");
const monitor_mod = @import("../monitor.zig");
const tiling = @import("tiling.zig");

const Client = client_mod.Client;
const Monitor = monitor_mod.Monitor;

pub const layout = monitor_mod.Layout{
    .symbol = "[\\]",
    .arrange_fn = dwindle,
};

pub fn dwindle(monitor: *Monitor) void {
    var n: u32 = 0;
    var counter = client_mod.nextTiled(monitor.clients);
    while (counter) |c| : (counter = client_mod.nextTiled(c.next)) {
        n += 1;
    }
    if (n == 0) return;

    const gap_outer_h = if (monitor.smartgaps_enabled and n == 1) 0 else monitor.gap_outer_h;
    const gap_outer_v = if (monitor.smartgaps_enabled and n == 1) 0 else monitor.gap_outer_v;
    const gap_inner_h = monitor.gap_inner_h;
    const gap_inner_v = monitor.gap_inner_v;

    const work_x: i32 = monitor.win_x + gap_outer_v;
    const work_y: i32 = monitor.win_y + gap_outer_h;
    const work_w: i32 = monitor.win_w - 2 * gap_outer_v;
    const work_h: i32 = monitor.win_h - 2 * gap_outer_h;

    var nx: i32 = work_x;
    var ny: i32 = 0;
    var nw: i32 = work_w;
    var nh: i32 = work_h;

    var i: u32 = 0;
    var current = client_mod.nextTiled(monitor.clients);
    while (current) |c| : (current = client_mod.nextTiled(c.next)) {
        const bw = c.border_width;
        const can_split = (i % 2 == 1 and @divTrunc(nh, 2) > 2 * bw) or
            (i % 2 == 0 and @divTrunc(nw, 2) > 2 * bw);

        if (can_split) {
            if (i + 1 < n) {
                if (i % 2 == 1) {
                    nh = @divTrunc(nh - gap_inner_h, 2);
                } else {
                    nw = @divTrunc(nw - gap_inner_v, 2);
                }
            }
            switch (i % 4) {
                0 => ny += nh + gap_inner_h,
                1 => nx += nw + gap_inner_v,
                2 => ny += nh + gap_inner_h,
                3 => nx += nw + gap_inner_v,
                else => unreachable,
            }
            if (i == 0) {
                if (n != 1) {
                    nw = @intFromFloat(@as(f32, @floatFromInt(work_w - gap_inner_v)) * monitor.mfact);
                }
                ny = work_y;
            } else if (i == 1) {
                nw = work_w - nw - gap_inner_v;
            }
            i += 1;
        }

        tiling.resize(c, nx, ny, nw - 2 * bw, nh - 2 * bw, false);
    }
}
