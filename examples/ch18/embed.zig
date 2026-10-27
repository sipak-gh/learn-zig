const std = @import("std");

// The path is relative to this source file. The bytes become part of the
// executable; banner.txt is not needed at run time.
const banner = @embedFile("banner.txt");

// Everything below runs at compile time: banner is comptime-known.
const first_line = banner[0 .. std.mem.findScalar(u8, banner, '\n').? + 1];
const line_count = std.mem.countScalar(u8, banner, '\n');
const shouted = "== " ++ first_line;

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    try out.print("type: {s}\n", .{@typeName(@TypeOf(banner))});
    try out.print("lines: {d}\n", .{line_count});
    try out.writeAll(shouted);
    try out.writeAll(banner);
    try out.flush();
}
