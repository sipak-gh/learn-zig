const std = @import("std");

pub fn main() void {
    // Unsigned: `/` and `%` are unambiguous.
    const a: u32 = 7;
    std.debug.print("7 / 2 = {d}, 7 % 2 = {d}\n", .{ a / 2, a % 2 });

    // Signed: say which rounding you want.
    const n: i32 = -7;
    const d: i32 = 2;
    std.debug.print("@divTrunc(-7, 2) = {d}\n", .{@divTrunc(n, d)}); // toward zero: -3
    std.debug.print("@divFloor(-7, 2) = {d}\n", .{@divFloor(n, d)}); // toward -inf: -4
    std.debug.print("@rem(-7, 2) = {d}\n", .{@rem(n, d)}); // sign of dividend: -1
    std.debug.print("@mod(-7, 2) = {d}\n", .{@mod(n, d)}); // never negative: 1

    // Floats: `/` is ordinary division.
    const f: f64 = -7;
    std.debug.print("-7.0 / 2 = {d}\n", .{f / 2});
}
