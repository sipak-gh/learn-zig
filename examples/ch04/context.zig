const std = @import("std");

// Zig has no closures. Put the captured data in a struct and give the
// struct a function that uses it (Chapter 7 covers structs and methods).
const Scaler = struct {
    factor: i32,

    fn apply(self: Scaler, x: i32) i32 {
        return x * self.factor;
    }
};

fn applyAll(values: []i32, scaler: Scaler) void {
    for (values) |*v| {
        v.* = scaler.apply(v.*);
    }
}

pub fn main() void {
    var factor: i32 = 10;
    factor += 0; // known only at run time
    var values = [_]i32{ 1, 2, 3 };
    applyAll(&values, .{ .factor = factor });
    std.debug.print("scaled: {any}\n", .{values});
}
