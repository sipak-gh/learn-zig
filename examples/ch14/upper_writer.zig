const std = @import("std");
const Writer = std.Io.Writer;

/// A std.Io.Writer that upper-cases everything and passes it on to
/// another writer.
const UpperWriter = struct {
    out: *Writer,
    drains: usize = 0,
    /// The interface. Callers use `&upper.writer`; it must not be copied
    /// out of the UpperWriter, or `drain` can't find its way back.
    writer: Writer,

    fn init(out: *Writer, buffer: []u8) UpperWriter {
        return .{
            .out = out,
            .writer = .{ .vtable = &.{ .drain = drain }, .buffer = buffer },
        };
    }

    /// Called when `buffer` is full, and by `flush`. Must consume the
    /// buffered bytes first, then `data`, whose last element counts
    /// `splat` times. Returns how many bytes of `data` it consumed.
    fn drain(w: *Writer, data: []const []const u8, splat: usize) Writer.Error!usize {
        const self: *UpperWriter = @alignCast(@fieldParentPtr("writer", w));
        self.drains += 1;
        try self.emit(w.buffer[0..w.end]);
        w.end = 0;

        var consumed: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            try self.emit(bytes);
            consumed += bytes.len;
        }
        const pattern = data[data.len - 1];
        for (0..splat) |_| {
            try self.emit(pattern);
            consumed += pattern.len;
        }
        return consumed;
    }

    fn emit(self: *UpperWriter, bytes: []const u8) Writer.Error!void {
        for (bytes) |byte| try self.out.writeByte(std.ascii.toUpper(byte));
    }
};

pub fn main() !void {
    var result: [256]u8 = undefined;
    var out: Writer = .fixed(&result);

    var buffer: [16]u8 = undefined;
    var upper: UpperWriter = .init(&out, &buffer);
    const w = &upper.writer; // a pointer to the field, never a copy

    try w.writeAll("hello, ");
    try w.print("{s} has {d} letters", .{ "zig", 3 });
    try w.print(" and a [{s:->8}]\n", .{"pad"});
    try w.writeAll("bye\n");
    std.debug.print("before flush: {d} drains, {d} bytes still buffered\n", .{ upper.drains, w.end });
    try w.flush();
    std.debug.print("after flush:  {d} drains\n", .{upper.drains});
    std.debug.print("{s}", .{out.buffered()});
}
