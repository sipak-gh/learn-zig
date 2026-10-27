const std = @import("std");

pub fn main() void {
    // @Int builds an integer type from a signedness and a bit count.
    const U12 = @Int(.unsigned, 12);
    const max: U12 = std.math.maxInt(U12);
    std.debug.print("{s}: max {d}\n", .{ @typeName(U12), max });

    // @Tuple builds a tuple type from a list of field types.
    const Row = @Tuple(&.{ []const u8, u32 });
    const row: Row = .{ "fox", 3 };
    std.debug.print("{s}: {s} {d}\n", .{ @typeName(Row), row[0], row[1] });

    // @Enum builds an enum from a tag type, names, and values.
    const Level = @Enum(u8, .exhaustive, &.{ "low", "high" }, &.{ 1, 10 });
    const level: Level = .high;
    std.debug.print("Level.{t} = {d}\n", .{ level, @backingInt(level) });

    // @Struct builds a struct type. Here: every field of Point, as an optional.
    const Patch = Partial(Point);
    const patch: Patch = .{ .y = 7 };
    std.debug.print("patch: x={?d} y={?d}\n", .{ patch.x, patch.y });
}

const Point = struct { x: i32, y: i32 };

/// A struct with the same field names as T, but every field optional and
/// defaulting to null.
fn Partial(comptime T: type) type {
    const info = @typeInfo(T).@"struct";
    var types: [info.field_names.len]type = undefined;
    var attrs: [info.field_names.len]std.lang.Type.Struct.FieldAttributes = undefined;
    for (info.field_types, 0..) |FieldType, i| {
        types[i] = ?FieldType;
        const default: ?FieldType = null;
        attrs[i] = .{ .default_value_ptr = &default };
    }
    return @Struct(.auto, null, info.field_names, &types, &attrs);
}
