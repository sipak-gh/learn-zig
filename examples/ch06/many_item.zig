const std = @import("std");

pub fn main() void {
    var data = [_]u8{ 'z', 'i', 'g', '!' };
    const slice: []u8 = &data;

    // A slice is made of a many-item pointer (`.ptr`) and a length (`.len`).
    const many: [*]u8 = slice.ptr;
    std.debug.print("type of slice.ptr: {s}\n", .{@typeName(@TypeOf(many))});

    // You can index a many-item pointer, but it has no length and no
    // bounds check: many[100] would compile and read garbage.
    many[0] = 'Z';
    std.debug.print("many[0..3] = {s}\n", .{many[0..3]});

    // Pointer arithmetic moves the pointer by whole elements.
    const from_second = many + 1;
    std.debug.print("from_second[0] = {c}\n", .{from_second[0]});

    // Give it a length again by slicing: now it is safe to use.
    const back: []u8 = many[0..data.len];
    std.debug.print("back = {s}, len {d}\n", .{ back, back.len });
}
