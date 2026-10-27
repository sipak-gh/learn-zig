const std = @import("std");
const testing = std.testing;

/// Reverses `bytes` in place.
fn reverse(bytes: []u8) void {
    if (bytes.len < 2) return;
    var i: usize = 0;
    var j = bytes.len - 1;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) std.mem.swap(u8, &bytes[i], &bytes[j]);
}

test "fuzz reverse" {
    // The corpus holds starting inputs. `zig test` runs testOne once for
    // each of them (and once with an empty input).
    try testing.fuzz({}, reverseTwice, .{ .corpus = &.{ "fox", "ab" } });
}

/// Property: reversing twice gives back the original bytes.
fn reverseTwice(_: void, smith: *testing.Smith) !void {
    var buffer: [64]u8 = undefined;
    // `slice` fills a prefix of the buffer and returns its length.
    const input = buffer[0..smith.slice(&buffer)];
    var copy: [64]u8 = undefined;
    @memcpy(copy[0..input.len], input);

    reverse(copy[0..input.len]);
    reverse(copy[0..input.len]);
    try testing.expectEqualSlices(u8, input, copy[0..input.len]);
}
