const std = @import("std");

pub fn main() void {
    for (0..6) |i| {
        // `i % 3` is always 0, 1 or 2; the `else` can't happen.
        const word = switch (i % 3) {
            0 => "fizz",
            1 => "buzz",
            2 => "boom",
            else => unreachable,
        };
        std.debug.print("{d}: {s}\n", .{ i, word });
    }
}
