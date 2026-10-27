const std = @import("std");

/// The type is an explicit comptime parameter.
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

/// The type is inferred from the first argument.
fn larger(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a > b) a else b;
}

/// Works for anything with a `len` field and indexing: arrays, slices,
/// and pointers to arrays.
fn first(items: anytype) @TypeOf(items[0]) {
    return items[0];
}

pub fn main() void {
    std.debug.print("max(u8, 3, 7) = {d}\n", .{max(u8, 3, 7)});
    std.debug.print("max(f64, 2.5, -1) = {d}\n", .{max(f64, 2.5, -1)});

    const a: i32 = -4;
    std.debug.print("larger(a, 10) = {d}\n", .{larger(a, 10)});
    std.debug.print("@TypeOf(larger(a, 10)) = {s}\n", .{@typeName(@TypeOf(larger(a, 10)))});

    const array = [_]u16{ 10, 20, 30 };
    const slice: []const u16 = &array;
    std.debug.print("first: {d} {d} {c}\n", .{ first(array), first(slice), first("zig") });
}
