const std = @import("std");

const Settings = struct {
    verbose: bool = false,
    level: u8 = 1,
    name: []const u8 = "default",

    pub const version = 2;
};

/// Sets the field called `name` (a comptime string) to `value`.
fn set(settings: *Settings, comptime name: []const u8, value: @FieldType(Settings, name)) void {
    @field(settings, name) = value;
}

/// Prints `name=value` for every field, whatever the struct.
fn dump(value: anytype) void {
    const T = @TypeOf(value);
    inline for (@typeInfo(T).@"struct".field_names) |name| {
        const field = @field(value, name);
        if (@TypeOf(field) == []const u8) {
            std.debug.print("  {s}={s}\n", .{ name, field });
        } else {
            std.debug.print("  {s}={any}\n", .{ name, field });
        }
    }
}

pub fn main() void {
    var s: Settings = .{};
    set(&s, "level", 3);
    set(&s, "name", "seek");
    std.debug.print("settings:\n", .{});
    dump(s);

    std.debug.print("@FieldType(Settings, \"level\") = {s}\n", .{@typeName(@FieldType(Settings, "level"))});
    std.debug.print("@hasField(Settings, \"level\") = {}\n", .{@hasField(Settings, "level")});
    std.debug.print("@hasField(Settings, \"version\") = {}\n", .{@hasField(Settings, "version")});
    std.debug.print("@hasDecl(Settings, \"version\") = {}\n", .{@hasDecl(Settings, "version")});
    // @field also reads declarations.
    std.debug.print("@field(Settings, \"version\") = {d}\n", .{@field(Settings, "version")});
}
