const std = @import("std");
const Writer = std.Io.Writer;

const Score = struct { name: []const u8, points: u32 };

/// Two output formats. Neither knows where the bytes go: a file, a
/// terminal, or memory. That is the caller's choice of *Writer.
const Format = union(enum) {
    text: struct { width: usize },
    csv,

    fn write(format: Format, w: *Writer, scores: []const Score) Writer.Error!void {
        switch (format) {
            .text => |text| for (scores) |s| {
                try w.print("{s}", .{s.name});
                try w.splatByteAll('.', text.width -| s.name.len);
                try w.print("{d}\n", .{s.points});
            },
            .csv => {
                try w.writeAll("name,points\n");
                for (scores) |s| try w.print("{s},{d}\n", .{ s.name, s.points });
            },
        }
    }
};

const example_scores = [_]Score{ .{ .name = "ada", .points = 42 }, .{ .name = "grace", .points = 7 } };

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;
    try Format.write(.{ .text = .{ .width = 8 } }, stdout, &example_scores);
    try Format.write(.csv, stdout, &example_scores);
    try stdout.flush();
}

test "text format, into growable memory" {
    var out: Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try Format.write(.{ .text = .{ .width = 8 } }, &out.writer, &example_scores);
    try std.testing.expectEqualStrings("ada.....42\ngrace...7\n", out.written());
}

test "csv format, into a fixed buffer" {
    var buffer: [64]u8 = undefined;
    var w: Writer = .fixed(&buffer);
    try Format.write(.csv, &w, &example_scores);
    try std.testing.expectEqualStrings("name,points\nada,42\ngrace,7\n", w.buffered());
}

test "a fixed buffer that is too small fails" {
    var buffer: [10]u8 = undefined;
    var w: Writer = .fixed(&buffer);
    try std.testing.expectError(error.WriteFailed, Format.write(.csv, &w, &example_scores));
}
