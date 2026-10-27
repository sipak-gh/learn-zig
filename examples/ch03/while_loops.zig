const std = @import("std");

pub fn main() void {
    // The plain form: repeat while the condition holds.
    var n: u32 = 1;
    while (n < 100) {
        n *= 3;
    }
    std.debug.print("first power of 3 >= 100: {d}\n", .{n});

    // A continue expression runs after each iteration, even after `continue`.
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        if (i % 3 != 0) continue;
        std.debug.print("{d} ", .{i});
    }
    std.debug.print("\n", .{});

    // `else` runs when the condition becomes false, but not after `break`.
    var j: u32 = 0;
    const found = while (j < 5) : (j += 1) {
        if (j * j == 9) break true;
    } else false;
    std.debug.print("found a square of 9 below 5: {}\n", .{found});
}
