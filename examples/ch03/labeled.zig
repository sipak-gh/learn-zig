const std = @import("std");

pub fn main() void {
    // Find the first pair (a, b) with a * b == 12 and a < b.
    outer: for (1..5) |a| {
        for (1..13) |b| {
            if (a >= b) continue; // next b
            if (a * b == 12) {
                std.debug.print("found {d} * {d}\n", .{ a, b });
                break :outer; // leave both loops
            }
        }
    }

    // `continue :outer` jumps to the next iteration of the outer loop.
    rows: for (0..3) |row| {
        for (0..3) |col| {
            if (col > row) continue :rows;
            std.debug.print("({d},{d}) ", .{ row, col });
        }
    }
    std.debug.print("\n", .{});

    // A labeled block is an expression: `break :label value` gives its value.
    var x: i32 = -4;
    x += 0;
    const magnitude = blk: {
        if (x < 0) break :blk -x;
        break :blk x;
    };
    std.debug.print("magnitude: {d}\n", .{magnitude});
}
