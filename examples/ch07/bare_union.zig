const std = @import("std");

/// A bare union has no tag. Only one field is valid at a time, and in safe
/// builds Zig keeps a hidden tag to check which one.
const Number = union {
    int: i64,
    float: f64,
};

pub fn main() void {
    var n: Number = .{ .int = 42 };
    std.debug.print("int: {d}\n", .{n.int});

    n = .{ .float = 2.5 }; // switch the active field by assigning a whole value
    std.debug.print("float: {d}\n", .{n.float});

    std.debug.print("int again: {d}\n", .{n.int}); // wrong field: panic
}
