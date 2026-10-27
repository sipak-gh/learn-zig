const std = @import("std");

pub fn main() void {
    // The input is a constant we wrote ourselves, so parsing can't fail.
    // `catch unreachable` says so; a safe build panics if we're wrong.
    const port = std.fmt.parseInt(u16, "8080", 10) catch unreachable;
    std.debug.print("port: {d}\n", .{port});
}
