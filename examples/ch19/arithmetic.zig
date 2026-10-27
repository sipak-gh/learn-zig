const std = @import("std");

pub fn main() void {
    const a: u8 = 250;
    const b: u8 = 10;

    // Wrapping: modulo 2^8, like C's unsigned arithmetic.
    std.debug.print("wrapping:   {d}\n", .{a +% b});
    // Saturating: stops at the type's limits.
    std.debug.print("saturating: {d}\n", .{a +| b});
    std.debug.print("saturating: {d}\n", .{@as(u8, 5) -| 10});

    // Checked: overflow becomes an error you handle.
    if (std.math.add(u8, a, b)) |sum| {
        std.debug.print("checked:    {d}\n", .{sum});
    } else |err| {
        std.debug.print("checked:    {t}\n", .{err});
    }

    // The builtin returns the wrapped result and an overflow bit.
    const sum, const overflowed = @addWithOverflow(a, b);
    std.debug.print("builtin:    {d}, overflow bit {d}\n", .{ sum, overflowed });

    // Signed integers too: the minimum has no positive counterpart.
    const min: i8 = std.math.minInt(i8);
    std.debug.print("-%({d}) = {d}\n", .{ min, -%min });
}
