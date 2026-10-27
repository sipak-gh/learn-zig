const std = @import("std");

/// Returns a new string with the bytes of `s` in reverse order.
/// The caller owns the result.
fn reversed(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    const out = try gpa.alloc(u8, s.len);
    for (s, 0..) |c, i| out[s.len - 1 - i] = c;
    return out;
}

test "reversed frees properly" {
    const gpa = std.testing.allocator;
    const r = try reversed(gpa, "stressed");
    defer gpa.free(r);
    try std.testing.expectEqualStrings("desserts", r);
}

test "reversed leaks" {
    const gpa = std.testing.allocator;
    const r = try reversed(gpa, "drawer");
    try std.testing.expectEqualStrings("reward", r);
}
