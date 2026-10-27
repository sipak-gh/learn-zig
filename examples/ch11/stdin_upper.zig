const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var in_buffer: [4096]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);
    const in = &stdin_reader.interface;

    var out_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), io, &out_buffer);
    const out = &stdout_writer.interface;

    var count: usize = 0;
    while (in.takeDelimiter('\n')) |maybe_line| {
        const line = maybe_line orelse break;
        count += 1;
        for (line) |c| try out.writeByte(std.ascii.toUpper(c));
        try out.writeByte('\n');
    } else |err| switch (err) {
        // The File.Reader keeps the real OS error in `err`.
        error.ReadFailed => return stdin_reader.err.?,
        error.StreamTooLong => return error.LineTooLong,
    }
    try out.print("{d} lines\n", .{count});
    try out.flush();
}
