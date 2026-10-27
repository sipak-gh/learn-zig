const std = @import("std");

pub fn main() void {
    var x: u8 = 250;
    x += 5; // 255: fine

    // Pick the overflow behavior you want, explicitly:
    const wrapped = x +% 10; // wrapping: 265 mod 256 = 9
    const saturated = x +| 10; // saturating: stops at 255
    const result, const overflowed = @addWithOverflow(x, 10); // result + a flag

    std.debug.print("wrapped={d} saturated={d}\n", .{ wrapped, saturated });
    std.debug.print("@addWithOverflow: result={d} overflowed={d}\n", .{ result, overflowed });

    const small: i8 = -128;
    std.debug.print("-%(-128) = {d}, 0 -% 1 as u8 = {d}\n", .{ -%small, @as(u8, 0) -% 1 });
}
