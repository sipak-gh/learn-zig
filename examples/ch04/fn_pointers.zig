const std = @import("std");

fn double(x: i32) i32 {
    return x * 2;
}

fn negate(x: i32) i32 {
    return -x;
}

// `op` is a pointer to any function that takes an i32 and returns an i32.
fn applyAll(values: []i32, op: *const fn (i32) i32) void {
    for (values) |*v| {
        v.* = op(v.*);
    }
}

pub fn main() void {
    var values = [_]i32{ 1, 2, 3 };
    applyAll(&values, &double);
    std.debug.print("doubled: {any}\n", .{values});
    applyAll(&values, &negate);
    std.debug.print("negated: {any}\n", .{values});

    // A function pointer can be stored and chosen at run time.
    var choice: u8 = 1;
    choice += 0;
    const op: *const fn (i32) i32 = if (choice == 0) &double else &negate;
    std.debug.print("op(5) = {d}\n", .{op(5)});
}
