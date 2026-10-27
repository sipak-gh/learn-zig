const std = @import("std");
const testing = std.testing;
const Io = std.Io;

/// Writes `items` as a bulleted list.
fn writeList(w: *Io.Writer, items: []const []const u8) Io.Writer.Error!void {
    for (items) |item| try w.print("- {s}\n", .{item});
}

test "writeList into a fixed buffer" {
    var buffer: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try writeList(&w, &.{ "fox", "dog" });
    // `buffered` is what has been written so far.
    try testing.expectEqualStrings("- fox\n- dog\n", w.buffered());
}

test "a fixed buffer that is too small" {
    var buffer: [4]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try testing.expectError(error.WriteFailed, writeList(&w, &.{"fox"}));
}

test "writeList into an allocating writer" {
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    try writeList(&out.writer, &.{ "a", "b", "c" });
    try testing.expectEqualStrings("- a\n- b\n- c\n", out.written());
}
