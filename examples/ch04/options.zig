const std = @import("std");

// Zig has no default arguments. Instead, take an options struct whose
// fields have default values.
const BannerOptions = struct {
    width: usize = 20,
    fill: u8 = '=',
    shout: bool = false,
};

fn banner(title: []const u8, options: BannerOptions) void {
    for (0..options.width) |_| std.debug.print("{c}", .{options.fill});
    std.debug.print("\n{s}{s}\n", .{ title, if (options.shout) "!" else "" });
}

pub fn main() void {
    banner("defaults", .{});
    banner("custom", .{ .width = 10, .fill = '*', .shout = true });
}
