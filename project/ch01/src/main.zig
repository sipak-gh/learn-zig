const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // Program output goes to stdout through a buffered writer. The buffer
    // lives on the stack; nothing reaches the terminal until we flush.
    // "Streaming" means: just append, the way a terminal or pipe works. (The
    // plain `.init` would write at explicit file offsets, starting at 0,
    // which can overwrite earlier output when stdout is redirected to a file.)
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("usage: seek [OPTIONS] PATTERN [PATH ...]\n", .{});
    try stdout.flush(); // Don't forget to flush!
}
