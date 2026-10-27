const std = @import("std");

pub fn main() void {
    // An array has a length that is part of its type: [3]u8.
    const primes = [3]u8{ 2, 3, 5 };
    // `_` lets the compiler count the elements for you.
    const vowels = [_]u8{ 'a', 'e', 'i', 'o', 'u' };
    // A result type lets you drop the type from the literal.
    const origin: [2]i32 = .{ 0, 0 };
    // @splat fills every element with one value.
    const zeros: [4]u16 = @splat(0);

    std.debug.print("primes: {any}, len {d}\n", .{ primes, primes.len });
    std.debug.print("vowels: {s}, len {d}\n", .{ &vowels, vowels.len });
    std.debug.print("origin: {any}, zeros: {any}\n", .{ origin, zeros });
    std.debug.print("type of primes: {s}\n", .{@typeName(@TypeOf(primes))});

    // Arrays are values. Assignment copies every element.
    var copy = primes;
    copy[0] = 99;
    std.debug.print("primes[0] = {d}, copy[0] = {d}\n", .{ primes[0], copy[0] });

    // Loop by value, or by pointer to change elements in place.
    var squares: [5]u32 = undefined;
    for (&squares, 0..) |*sq, i| sq.* = @intCast(i * i);
    var sum: u32 = 0;
    for (squares) |sq| sum += sq;
    std.debug.print("squares: {any}, sum {d}\n", .{ squares, sum });

    // Arrays of the same type compare with std.mem.eql (on slices), not ==.
    std.debug.print("equal: {}\n", .{std.mem.eql(u8, &primes, &[_]u8{ 2, 3, 5 })});
}
