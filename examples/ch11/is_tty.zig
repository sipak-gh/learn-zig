const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const stdout_tty = try std.Io.File.stdout().isTty(io);
    const stdin_tty = try std.Io.File.stdin().isTty(io);
    std.debug.print("stdout is a terminal: {}\n", .{stdout_tty});
    std.debug.print("stdin is a terminal:  {}\n", .{stdin_tty});
}
