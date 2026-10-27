const std = @import("std");
const testing = std.testing;

fn double(x: i32) i32 {
    return x + x + 1; // bug!
}

test "double" {
    try testing.expectEqual(8, double(4));
}

test "greeting" {
    try testing.expectEqualStrings("hello, fox", "hello, dog");
}

test "this one passes" {
    try testing.expect(true);
}
