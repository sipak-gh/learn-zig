const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;

    std.debug.print("debug: starting\n", .{}); // stderr, right away
    try stdout.print("result: 42\n", .{}); // stdout, buffered
    std.debug.print("debug: done\n", .{});
    try stdout.flush(); // "result: 42" is written here
}
