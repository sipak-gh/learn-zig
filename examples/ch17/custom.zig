const std = @import("std");

const Point = struct {
    x: i32,
    y: i32,

    /// Called by std.json instead of the default field-by-field output.
    /// `jw` is a *std.json.Stringify.
    pub fn jsonStringify(self: Point, jw: anytype) !void {
        try jw.print("\"{d},{d}\"", .{ self.x, self.y });
    }
};

const Path = struct {
    name: []const u8,
    points: []const Point,
    secret: []const u8,

    /// Writes only some fields, under different names.
    pub fn jsonStringify(self: Path, jw: anytype) !void {
        try jw.beginObject();
        try jw.objectField("id");
        try jw.write(self.name);
        try jw.objectField("pts");
        try jw.write(self.points);
        try jw.endObject();
    }
};

pub fn main(init: std.process.Init) !void {
    var buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    const path: Path = .{
        .name = "trail",
        .points = &.{ .{ .x = 1, .y = 2 }, .{ .x = -3, .y = 4 } },
        .secret = "do not print",
    };
    try out.print("{f}\n", .{std.json.fmt(path, .{})});
    try out.flush();
}
