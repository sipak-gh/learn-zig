const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("You will never see this line.\n", .{});
    // Missing: try stdout.flush();
}
