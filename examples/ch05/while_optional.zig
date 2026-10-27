const std = @import("std");

pub fn main() void {
    // splitScalar returns an iterator. Its next() returns ?[]const u8:
    // the next piece, or null when there are no more.
    var words = std.mem.splitScalar(u8, "red,green,blue", ',');

    // `while` with a capture loops until next() returns null.
    while (words.next()) |word| {
        std.debug.print("word: {s}\n", .{word});
    }

    // `orelse` can also leave the function or the loop.
    var parts = std.mem.splitScalar(u8, "a=1", '=');
    const key = parts.next() orelse return;
    const value = parts.next() orelse return;
    std.debug.print("key={s} value={s}\n", .{ key, value });
}
