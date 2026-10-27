const std = @import("std");
const greet = @import("greet.zig"); // path relative to this file

pub fn main() void {
    std.debug.print("{s}, world!\n", .{greet.greeting});
    std.debug.print("shout(2) = {d}\n", .{greet.shout(2)});
    std.debug.print("greet is a {s} named {s}\n", .{ @typeName(@TypeOf(greet)), @typeName(greet) });
}
