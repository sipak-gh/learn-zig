const std = @import("std");

// Parameters are `name: Type`. The return type comes after the parentheses.
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// A function that returns nothing returns `void`.
fn greet(name: []const u8) void {
    std.debug.print("hello, {s}\n", .{name});
}

// `pub` makes a function visible to files that @import this one.
pub fn square(x: i32) i32 {
    return x * x;
}

pub fn main() void {
    greet("zig");
    const sum = add(2, 3);
    std.debug.print("2 + 3 = {d}\n", .{sum});
    // Functions can be used before they are declared: order doesn't matter.
    std.debug.print("cube(3) = {d}\n", .{cube(3)});
    // A returned value must be used. Discard it explicitly with `_`.
    _ = square(4);
}

fn cube(x: i32) i32 {
    return x * square(x);
}
