//! Each case does something illegal. Run with a case name as the argument.

const std = @import("std");

const Shape = union(enum) { circle: f32, square: f32 };
const Color = enum(u8) { red, green, blue };

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const case = args[1];
    // A runtime number the compiler can't see through.
    const n: usize = args.len + 2; // 4 when there is one argument

    if (std.mem.eql(u8, case, "bounds")) {
        const items = [_]u8{ 1, 2, 3 };
        const i = n + 1;
        std.debug.print("{d}\n", .{items[i]});
    } else if (std.mem.eql(u8, case, "null")) {
        const maybe: ?usize = if (n > 100) n else null;
        std.debug.print("{d}\n", .{maybe.?});
    } else if (std.mem.eql(u8, case, "cast")) {
        const big: u32 = @intCast(n * 100);
        const small: u8 = @intCast(big);
        std.debug.print("{d}\n", .{small});
    } else if (std.mem.eql(u8, case, "unreachable")) {
        if (n != 0) unreachable;
    } else if (std.mem.eql(u8, case, "divide")) {
        const zero = n - 4;
        std.debug.print("{d}\n", .{100 / zero});
    } else if (std.mem.eql(u8, case, "enum")) {
        const color: Color = @fromBackingInt(@intCast(n));
        std.debug.print("{t}\n", .{color});
    } else if (std.mem.eql(u8, case, "union")) {
        const shape: Shape = if (n > 0) .{ .circle = 1 } else .{ .square = 2 };
        std.debug.print("{d}\n", .{shape.square});
    } else if (std.mem.eql(u8, case, "slice")) {
        const text = "hello";
        std.debug.print("{s}\n", .{text[n..2]});
    }
}
