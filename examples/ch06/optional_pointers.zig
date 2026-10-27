const std = @import("std");

/// Returns a pointer to the first even number, or null if there is none.
fn firstEven(numbers: []u32) ?*u32 {
    for (numbers) |*n| {
        if (n.* % 2 == 0) return n;
    }
    return null;
}

pub fn main() void {
    var numbers = [_]u32{ 3, 5, 8, 11, 12 };

    // Unwrap with `if`: inside the block `p` is a plain *u32.
    if (firstEven(&numbers)) |p| {
        p.* = 0; // change the array through the pointer
    }
    std.debug.print("numbers = {any}\n", .{numbers});

    var odd = [_]u32{ 1, 3 };
    const found = firstEven(&odd);
    std.debug.print("found in odd: {any}\n", .{found});

    // `.?` unwraps when you know it can't be null (it panics if it is).
    const zero = firstEven(&numbers).?;
    std.debug.print("zero.* = {d}\n", .{zero.*});

    // `orelse` supplies a fallback.
    var fallback: u32 = 42;
    const target = firstEven(&odd) orelse &fallback;
    std.debug.print("target.* = {d}\n", .{target.*});

    // Null is stored as address 0, so an optional pointer costs nothing extra.
    std.debug.print("@sizeOf(*u32) = {d}, @sizeOf(?*u32) = {d}\n", .{ @sizeOf(*u32), @sizeOf(?*u32) });
}
