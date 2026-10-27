const std = @import("std");

/// BUG: returns a slice of `buf`, which lives in this function's stack
/// frame. The memory is reused as soon as the function returns.
fn reversedBad(text: []const u8) []const u8 {
    var buf: [32]u8 = undefined;
    for (text, 0..) |c, i| buf[text.len - 1 - i] = c;
    return buf[0..text.len];
}

/// Fixed: the caller owns the buffer, so the result lives as long as the
/// caller's buffer does.
fn reversed(buf: []u8, text: []const u8) []u8 {
    const out = buf[0..text.len];
    for (text, 0..) |c, i| out[text.len - 1 - i] = c;
    return out;
}

pub fn main() void {
    const bad = reversedBad("stressed");
    std.debug.print("bad:  {s}\n", .{bad});

    var buf: [32]u8 = undefined;
    const good = reversed(&buf, "stressed");
    std.debug.print("good: {s}\n", .{good});
}
