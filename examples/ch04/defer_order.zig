const std = @import("std");

fn work(fail: bool) u8 {
    std.debug.print("start\n", .{});
    // `defer` runs its statement when the enclosing block exits,
    // however it exits: falling off the end or `return`.
    defer std.debug.print("cleanup 1\n", .{});
    defer std.debug.print("cleanup 2\n", .{}); // runs first: reverse order
    if (fail) {
        std.debug.print("bailing out early\n", .{});
        return 1;
    }
    std.debug.print("finished\n", .{});
    return 0;
}

pub fn main() void {
    _ = work(false);
    std.debug.print("---\n", .{});
    _ = work(true);
    std.debug.print("---\n", .{});

    // Defers belong to the block they're in, so in a loop they run at the
    // end of every iteration.
    for (0..2) |i| {
        defer std.debug.print("end of iteration {d}\n", .{i});
        std.debug.print("iteration {d}\n", .{i});
    }
}
