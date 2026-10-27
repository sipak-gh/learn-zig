const std = @import("std");

pub fn main() void {
    const sunny = true;
    const warm = false;
    std.debug.print("and={} or={} not={}\n", .{ sunny and warm, sunny or warm, !sunny });
    std.debug.print("as int: {d}\n", .{@intFromBool(sunny)});

    // `void` has exactly one value, written `{}`. It takes no space.
    const nothing: void = {};
    std.debug.print("void: {any}, size {d}\n", .{ nothing, @sizeOf(void) });
}
