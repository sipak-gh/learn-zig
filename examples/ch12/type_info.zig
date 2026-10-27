const std = @import("std");

/// Prints a one-line description of any type, using reflection.
fn describe(comptime T: type) void {
    switch (@typeInfo(T)) {
        .int => |info| std.debug.print("{s}: {t} integer, {d} bits\n", .{ @typeName(T), info.signedness, info.bits }),
        .optional => |info| std.debug.print("{s}: optional {s}\n", .{ @typeName(T), @typeName(info.child) }),
        .@"enum" => |info| {
            std.debug.print("{s}: enum with", .{@typeName(T)});
            for (info.field_names) |name| std.debug.print(" .{s}", .{name});
            std.debug.print("\n", .{});
        },
        .@"struct" => |info| {
            std.debug.print("{s}: struct with {d} fields\n", .{ @typeName(T), info.field_names.len });
            // field_names, field_types and field_attrs are parallel arrays.
            // `inline for`: FieldType is a type, so it must be comptime-known.
            inline for (info.field_names, info.field_types, info.field_attrs) |name, FieldType, attrs| {
                const default = if (attrs.default_value_ptr != null) " (has default)" else "";
                std.debug.print("  {s}: {s}{s}\n", .{ name, @typeName(FieldType), default });
            }
            for (info.decl_names) |name| std.debug.print("  pub decl {s}\n", .{name});
        },
        else => std.debug.print("{s}: {t}\n", .{ @typeName(T), @typeInfo(T) }),
    }
}

const Color = enum { red, green, blue };

const Config = struct {
    name: []const u8,
    retries: u8 = 3,
    color: ?Color = null,

    pub const default_name = "seek";
};

pub fn main() void {
    describe(u7);
    describe(i64);
    describe(?f32);
    describe(Color);
    describe(Config);
    describe(bool);
}
