const std = @import("std");

const Pair = struct { a: i32, b: i32 };

pub fn main() void {
    // Looks like a swap, but Zig writes each field straight into `p`:
    // p.a = p.b; then p.b = p.a (which is already overwritten).
    var p: Pair = .{ .a = 1, .b = 2 };
    p = .{ .a = p.b, .b = p.a };
    std.debug.print("broken swap: a={d} b={d}\n", .{ p.a, p.b });

    // Copy the old value first.
    var q: Pair = .{ .a = 1, .b = 2 };
    const old = q;
    q = .{ .a = old.b, .b = old.a };
    std.debug.print("real swap:   a={d} b={d}\n", .{ q.a, q.b });
}
