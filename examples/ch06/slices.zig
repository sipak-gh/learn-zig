const std = @import("std");

pub fn main() void {
    var numbers = [_]i32{ 10, 20, 30, 40, 50 };

    // A runtime index makes a slice: a pointer plus a length.
    var start: usize = 1;
    _ = &start; // pretend `start` could change, so it is runtime-known
    const middle = numbers[start..4];
    std.debug.print("middle = {any}, len {d}\n", .{ middle, middle.len });

    // A slice points into the array. Writing through it changes the array.
    middle[0] = 99;
    std.debug.print("numbers = {any}\n", .{numbers});

    // Omit the end to slice to the end. Slicing a slice gives another view.
    const rest = numbers[start..];
    const last_two = rest[rest.len - 2 ..];
    std.debug.print("rest = {any}, last_two = {any}\n", .{ rest, last_two });

    // `&array` is a pointer to the whole array; it coerces to a slice.
    const all: []const i32 = &numbers;
    std.debug.print("sum = {d}\n", .{sum(all)});
    std.debug.print("sum of middle = {d}\n", .{sum(middle)});

    // A slice is two machine words, whatever its length.
    std.debug.print("@sizeOf([]i32) = {d}, @sizeOf([5]i32) = {d}\n", .{ @sizeOf([]i32), @sizeOf([5]i32) });

    // Comptime-known bounds give a pointer to an array, with the length in the type.
    const first_two = numbers[0..2];
    std.debug.print("type of numbers[0..2]: {s}\n", .{@typeName(@TypeOf(first_two))});
    std.debug.print("type of numbers[start..4]: {s}\n", .{@typeName(@TypeOf(middle))});

    // Empty slices are fine.
    const none = numbers[2..2];
    std.debug.print("none.len = {d}\n", .{none.len});
}

/// Works for any number of items: arrays, parts of arrays, heap memory.
fn sum(items: []const i32) i64 {
    var total: i64 = 0;
    for (items) |n| total += n;
    return total;
}
