const std = @import("std");
const builtin = @import("builtin");

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    // Both are comptime-known: code can branch on the build mode for free.
    try out.print("mode: {t}\n", .{builtin.mode});
    try out.print("runtime safety: {}\n", .{std.debug.runtime_safety});
    if (builtin.mode == .debug) try out.writeAll("(extra checks could go here)\n");
    try out.flush();
}
