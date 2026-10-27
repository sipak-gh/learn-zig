const std = @import("std");

const Color = enum { red, green };

const Item = struct {
    name: []const u8,
    count: u32,
    price: f64,
    in_stock: bool,
    color: Color,
    tags: []const []const u8,
    note: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    const item: Item = .{
        .name = "Fox \"Red\" Plush\t\\",
        .count = 3,
        .price = 12.5,
        .in_stock = true,
        .color = .red,
        .tags = &.{ "toy", "soft" },
    };

    // std.json.fmt wraps a value so that `{f}` prints it as JSON.
    try out.print("{f}\n", .{std.json.fmt(item, .{})});

    // Options: pretty-print, and leave out optional fields that are null.
    try out.print("{f}\n", .{std.json.fmt(item, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    })});

    // Anonymous structs, tuples, and plain values work too.
    try out.print("{f}\n", .{std.json.fmt(.{ .ok = true, .ids = .{ 1, 2, 3 } }, .{})});
    try out.print("{f}\n", .{std.json.fmt("caf\u{e9} \u{1F98A}", .{ .escape_unicode = true })});

    // Or get the JSON as an allocated string.
    const text = try std.json.Stringify.valueAlloc(init.gpa, item.tags, .{});
    defer init.gpa.free(text);
    try out.print("{s} ({d} bytes)\n", .{ text, text.len });

    try out.flush();
}
