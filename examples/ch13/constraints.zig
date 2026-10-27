const std = @import("std");

fn isNumber(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .float, .comptime_int, .comptime_float => true,
        else => false,
    };
}

/// Adds up a slice of numbers.
fn sum(comptime T: type, values: []const T) T {
    if (!comptime isNumber(T)) @compileError("sum: expected a number type, found " ++ @typeName(T));
    var total: T = 0;
    for (values) |v| total += v;
    return total;
}

/// Averages anything that coerces to a slice of floats or ints.
fn mean(values: anytype) f64 {
    const Values = @TypeOf(values);
    const Elem = switch (@typeInfo(Values)) {
        .pointer => |info| switch (info.size) {
            .slice => info.child,
            .one => @typeInfo(info.child).array.child, // pointer to array
            else => @compileError("mean: unsupported pointer " ++ @typeName(Values)),
        },
        .array => |info| info.child,
        else => @compileError("mean: expected an array or slice, found " ++ @typeName(Values)),
    };
    if (!comptime isNumber(Elem)) @compileError("mean: elements must be numbers, found " ++ @typeName(Elem));

    var total: f64 = 0;
    for (values) |v| total += switch (@typeInfo(Elem)) {
        .int => @floatFromInt(v),
        else => v,
    };
    return total / @as(f64, @floatFromInt(values.len));
}

pub fn main() void {
    const ints = [_]i32{ 4, 8, 15, 16, 23, 42 };
    const floats = [_]f32{ 0.5, 1.5 };
    std.debug.print("sum = {d}\n", .{sum(i32, &ints)});
    std.debug.print("mean(ints) = {d}\n", .{mean(ints)});
    std.debug.print("mean(&floats) = {d}\n", .{mean(&floats)});
    std.debug.print("mean(slice) = {d}\n", .{mean(@as([]const i32, ints[0..2]))});
}
