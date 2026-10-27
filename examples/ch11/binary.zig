const std = @import("std");

/// Reports whether the first `probe_len` bytes contain a NUL byte.
/// peek leaves the bytes in the reader, so reading can continue normally.
fn looksBinary(reader: *std.Io.Reader, probe_len: usize) !bool {
    const head = reader.peek(probe_len) catch |err| switch (err) {
        // Shorter input: everything there is is already buffered.
        error.EndOfStream => reader.buffered(),
        else => |e| return e,
    };
    return std.mem.findScalar(u8, head, 0) != null;
}

pub fn main() !void {
    const inputs = [_][]const u8{ "plain text\n", "fox\x00binary\n", "" };
    for (inputs) |bytes| {
        var r: std.Io.Reader = .fixed(bytes);
        const binary = try looksBinary(&r, 8);
        // Nothing was consumed: the first line is still there.
        const first = try r.takeDelimiter('\n') orelse "(empty)";
        std.debug.print("binary={} first line: \"{f}\"\n", .{ binary, std.zig.fmtString(first) });
    }
}
