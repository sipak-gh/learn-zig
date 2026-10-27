const std = @import("std");

pub fn main() void {
    // An array literal (Chapter 6 covers arrays and slices in depth).
    var scores = [_]u32{ 70, 85, 92 };

    // Iterate over the elements.
    var total: u32 = 0;
    for (scores) |s| {
        total += s;
    }
    std.debug.print("total: {d}\n", .{total});

    // Iterate over a range: 0, 1, 2, 3 (the end is excluded).
    for (0..4) |k| {
        std.debug.print("{d} ", .{k});
    }
    std.debug.print("\n", .{});

    // Several objects at once: here, the elements and a counter from 1.
    for (scores, 1..) |s, rank| {
        std.debug.print("#{d}: {d}\n", .{ rank, s });
    }

    // Capture a pointer with |*s| to change the elements in place.
    for (&scores) |*s| {
        s.* += 5;
    }
    std.debug.print("curved: {any}\n", .{scores});
}
