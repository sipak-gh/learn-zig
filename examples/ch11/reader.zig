const std = @import("std");

pub fn main() !void {
    // A Reader over bytes in memory. A File.Reader offers the same API.
    var r: std.Io.Reader = .fixed("#!seek\nfirst line\nsecond line\nlast, no newline");

    // peek looks at bytes without consuming them; toss consumes them.
    const magic = try r.peek(2);
    std.debug.print("peek: {s}\n", .{magic});
    if (std.mem.eql(u8, magic, "#!")) r.toss(2);

    // takeByte consumes one byte; discardDelimiterInclusive skips past '\n'.
    std.debug.print("byte: {c}\n", .{try r.takeByte()});
    _ = try r.discardDelimiterInclusive('\n');

    // takeDelimiter returns one line without its '\n', and null at the end.
    // The last line counts even without a trailing '\n'.
    while (try r.takeDelimiter('\n')) |line| {
        std.debug.print("line: \"{s}\" ({d} bytes)\n", .{ line, line.len });
    }
}
