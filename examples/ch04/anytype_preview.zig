const std = @import("std");

// `anytype` accepts an argument of any type. The compiler makes a separate
// copy of the function for each type it is called with (Chapter 13).
fn twice(x: anytype) @TypeOf(x) {
    return x + x;
}

pub fn main() void {
    const a: u8 = 21;
    const b: f64 = 1.25;
    std.debug.print("{d} {d}\n", .{ twice(a), twice(b) });
}
