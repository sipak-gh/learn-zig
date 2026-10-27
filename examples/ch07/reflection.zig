const std = @import("std");

const Settings = struct {
    verbose: bool = false,
    width: u16 = 80,
    name: []const u8 = "seek",
};

pub fn main() void {
    // Field names are known at compile time.
    for (std.meta.fieldNames(Settings)) |name| {
        std.debug.print("field: {s}\n", .{name});
    }

    // `@field` accesses a field by a compile-time name.
    var s: Settings = .{};
    @field(s, "width") = 120;
    std.debug.print("width = {d}, has 'color': {}\n", .{ s.width, @hasField(Settings, "color") });

    // `==` doesn't work on structs; std.meta.eql compares field by field.
    const t: Settings = .{ .width = 120 };
    std.debug.print("equal: {}\n", .{std.meta.eql(s, t)});
}
