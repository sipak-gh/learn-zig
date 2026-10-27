const std = @import("std");

pub fn main() void {
    var x: u8 = 250;
    std.debug.print("x = {d}\n", .{x});
    x += 10; // 260 doesn't fit in a u8: illegal behavior
    std.debug.print("x = {d}\n", .{x});
}
