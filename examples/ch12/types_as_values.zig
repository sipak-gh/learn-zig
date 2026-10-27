const std = @import("std");

/// Types are values of type `type`. This function takes one and returns one.
fn Pair(comptime T: type) type {
    return struct { first: T, second: T };
}

/// The smallest unsigned type that can hold `max`.
fn SmallestFor(comptime max: comptime_int) type {
    return if (max <= 255) u8 else if (max <= 65535) u16 else u32;
}

pub fn main() void {
    const Int = i32; // a type stored in a constant
    const x: Int = -5;
    std.debug.print("x: {s} = {d}\n", .{ @typeName(@TypeOf(x)), x });

    const p: Pair(f32) = .{ .first = 1.5, .second = 2.5 };
    std.debug.print("p.first: {s}, Pair(f32) == Pair(f32): {}\n", .{
        @typeName(@TypeOf(p.first)),
        Pair(f32) == Pair(f32),
    });

    std.debug.print("SmallestFor(200) = {s}, SmallestFor(1000) = {s}\n", .{
        @typeName(SmallestFor(200)),
        @typeName(SmallestFor(1000)),
    });

    // @TypeOf works on any expression, without evaluating it at run time.
    std.debug.print("@TypeOf(1 + 2) = {s}, @TypeOf(\"hi\") = {s}\n", .{
        @typeName(@TypeOf(1 + 2)),
        @typeName(@TypeOf("hi")),
    });
}
