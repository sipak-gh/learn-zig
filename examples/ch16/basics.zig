const std = @import("std");
const testing = std.testing;

/// Returns the largest value in `items`, or null if it is empty.
fn max(items: []const i32) ?i32 {
    if (items.len == 0) return null;
    var best = items[0];
    for (items[1..]) |item| best = @max(best, item);
    return best;
}

// A test named with a string.
test "max finds the largest value" {
    try testing.expect(max(&.{ 3, 9, 2 }).? == 9);
    try testing.expectEqual(9, max(&.{ 3, 9, 2 }));
    try testing.expectEqual(null, max(&.{}));
}

// A test named after a declaration: a "doctest".
test max {
    try testing.expectEqual(-1, max(&.{ -5, -1, -3 }));
}

fn parseAge(text: []const u8) !u8 {
    const age = try std.fmt.parseInt(u8, text, 10);
    if (age > 150) return error.TooOld;
    return age;
}

test "parseAge" {
    try testing.expectEqual(42, try parseAge("42"));
    try testing.expectError(error.TooOld, parseAge("200"));
    try testing.expectError(error.InvalidCharacter, parseAge("4x"));
}

test "strings, slices and formatting" {
    try testing.expectEqualStrings("fox", "the fox"[4..]);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, &[_]u8{ 1, 2, 3 });
    try testing.expectFmt("[  42]", "[{d:>4}]", .{42});
}
