const std = @import("std");

// The file's bytes become a constant in the program, like a string
// literal. The path is relative to this source file.
const source = @embedFile("embed.zig");

// Comptime code can work on embedded data too.
const line_count = std.mem.countScalar(u8, source, '\n');

pub fn main() void {
    std.debug.print("this program's source: {d} bytes, {d} lines\n", .{ source.len, line_count });
    const first_line = source[0..std.mem.findScalar(u8, source, '\n').?];
    std.debug.print("first line: {s}\n", .{first_line});
}
