const std = @import("std");

const SetupError = error{DiskFull};

fn setup(fail: bool) SetupError!void {
    std.debug.print("open log\n", .{});
    defer std.debug.print("  defer: always runs\n", .{});
    // errdefer runs only if this function returns an error.
    errdefer std.debug.print("  errdefer: close log again\n", .{});

    if (fail) return error.DiskFull;
    std.debug.print("setup done\n", .{});
}

pub fn main() void {
    setup(false) catch {};
    std.debug.print("---\n", .{});
    setup(true) catch |err| std.debug.print("setup failed: {t}\n", .{err});
}
