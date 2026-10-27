const std = @import("std");

// The simplest `main`: no parameters, returns nothing.
pub fn main() void {
    std.debug.print("Hello, {s}! {d} + {d} = {d}\n", .{ "stderr", 2, 3, 2 + 3 });
}
