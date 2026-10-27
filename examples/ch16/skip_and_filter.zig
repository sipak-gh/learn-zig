const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

/// True only when this code is compiled by `zig test`.
fn inTest() bool {
    return builtin.is_test;
}

test "is_test" {
    try testing.expect(inTest());
}

test "only on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    try testing.expect(false); // never reached on Linux or macOS
}

test "math: add" {
    try testing.expectEqual(4, 2 + 2);
}

test "math: multiply" {
    try testing.expectEqual(6, 2 * 3);
}

// An unnamed test always runs, even with --test-filter.
test {
    try testing.expect(true);
}
