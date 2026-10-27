const std = @import("std");

pub fn main() void {
    const a: f32 = 1.5;
    const b: f64 = 1e-3; // scientific notation
    const c = 7.0 / 2.0; // comptime_float: 3.5
    const third: f64 = 1.0 / 3.0;

    std.debug.print("a={d} b={d} c={d}\n", .{ a, b, c });
    std.debug.print("third={d} rounded={d:.3}\n", .{ third, third });
    std.debug.print("0.1 + 0.2 = {d}\n", .{@as(f64, 0.1) + @as(f64, 0.2)});
    std.debug.print("sqrt(2) = {d:.5}, pi = {d:.5}\n", .{ @sqrt(@as(f64, 2)), std.math.pi });
    std.debug.print("inf={d} nan={d}\n", .{ std.math.inf(f64), std.math.nan(f64) });
}
