const std = @import("std");

pub fn main() void {
    const V = @Vector(4, i32);
    const a: V = .{ 1, 2, 3, 4 };
    const b: V = .{ 10, 20, 30, 40 };

    // Operators work lane by lane.
    std.debug.print("a + b  = {any}\n", .{a + b});
    std.debug.print("a * b  = {any}\n", .{a * b});

    // @splat fills every lane with one value.
    const twos: V = @splat(2);
    std.debug.print("a * 2  = {any}\n", .{a * twos});

    // Comparisons give a vector of bools; @reduce combines the lanes.
    const big = b > @as(V, @splat(15));
    std.debug.print("b > 15 = {any}\n", .{big});
    std.debug.print("any: {}, all: {}\n", .{ @reduce(.Or, big), @reduce(.And, big) });
    std.debug.print("sum of a = {d}\n", .{@reduce(.Add, a)});

    // Lanes can be read like array elements, and arrays coerce to vectors.
    const array: [4]i32 = .{ 5, 6, 7, 8 };
    const from_array: V = array;
    std.debug.print("lane 2 = {d}\n", .{from_array[2]});

    // @select picks each lane from one of two vectors.
    std.debug.print("select = {any}\n", .{@select(i32, big, a, b)});

    std.debug.print("suggested u8 lanes on this CPU: {?d}\n", .{std.simd.suggestVectorLength(u8)});
}
