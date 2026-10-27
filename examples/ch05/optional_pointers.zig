const std = @import("std");

// A pointer `*u32` can never be null. "Maybe a pointer" is `?*u32`.
fn largest(values: []u32) ?*u32 {
    if (values.len == 0) return null;
    var best = &values[0];
    for (values) |*v| {
        if (v.* > best.*) best = v;
    }
    return best;
}

pub fn main() void {
    var values = [_]u32{ 3, 9, 4 };
    if (largest(&values)) |p| {
        p.* = 0; // reset the largest value through the pointer
    }
    std.debug.print("values: {any}\n", .{values});

    // An optional pointer costs nothing: null is stored as address 0.
    std.debug.print("size of *u32: {d}, size of ?*u32: {d}\n", .{ @sizeOf(*u32), @sizeOf(?*u32) });
    std.debug.print("size of u32: {d}, size of ?u32: {d}\n", .{ @sizeOf(u32), @sizeOf(?u32) });
}
