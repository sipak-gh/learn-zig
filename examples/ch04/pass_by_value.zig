const std = @import("std");

// Parameters are constants. To change a value, make a local copy...
fn withFirstSetTo99(values: [3]u32) [3]u32 {
    var copy = values;
    copy[0] = 99;
    return copy;
}

// ...or take a pointer to the caller's value (Chapter 6 covers pointers).
fn bump(counter: *u32) void {
    counter.* += 1;
}

pub fn main() void {
    const original = [3]u32{ 1, 2, 3 };
    const changed = withFirstSetTo99(original);
    std.debug.print("original: {any}\n", .{original});
    std.debug.print("changed:  {any}\n", .{changed});

    var count: u32 = 0;
    bump(&count);
    bump(&count);
    std.debug.print("count: {d}\n", .{count});
}
