const std = @import("std");
const testing = std.testing;

/// Returns "<name>!" in new memory. The caller owns the result.
fn shout(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return gpa.print("{s}!", .{name});
}

test "shout" {
    const gpa = testing.allocator;
    const text = try shout(gpa, "fox");
    // Oops: no `defer gpa.free(text);`
    try testing.expectEqualStrings("fox!", text);
}
