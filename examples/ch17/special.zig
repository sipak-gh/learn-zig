const std = @import("std");

const Shape = union(enum) {
    circle: f64,
    square: struct { side: u32 },
    empty,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    // A tagged union becomes an object with one field: the active tag.
    const shapes = [_]Shape{ .{ .circle = 1.5 }, .{ .square = .{ .side = 2 } }, .empty };
    try out.print("{f}\n", .{std.json.fmt(shapes, .{})});

    // Bytes that are not valid UTF-8 can't be a JSON string, so they
    // become an array of numbers.
    try out.print("{f}\n", .{std.json.fmt("ok", .{})});
    try out.print("{f}\n", .{std.json.fmt("caf\xe9", .{})});

    // Errors and enum literals become strings.
    try out.print("{f}\n", .{std.json.fmt(.{ error.FileNotFound, .done }, .{})});
    try out.flush();
}
