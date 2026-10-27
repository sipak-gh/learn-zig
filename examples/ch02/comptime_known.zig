const std = @import("std");

const width = 4; // comptime-known: a literal
const height = width * 2; // computed by the compiler

pub fn main() void {
    // Array lengths must be known at compile time. `height` is.
    const grid: [height]u8 = undefined;

    // `var` values are runtime values, even when they look constant.
    var n: usize = 3;
    n += 1;

    std.debug.print("grid has {d} cells, n = {d}\n", .{ grid.len, n });
    std.debug.print("height is {s}, n is {s}\n", .{ @typeName(@TypeOf(height)), @typeName(@TypeOf(n)) });
}
