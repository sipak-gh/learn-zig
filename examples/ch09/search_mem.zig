const std = @import("std");
const mem = std.mem;

pub fn main() void {
    const line = "  error: disk full (disk 2)  \n";

    // Comparing: never use == on slices.
    std.debug.print("eql: {}\n", .{mem.eql(u8, "zig", "zig")});

    // Finding: every find* returns ?usize, null when there's no match.
    std.debug.print("find \"disk\":      {?d}\n", .{mem.find(u8, line, "disk")});
    std.debug.print("findLast \"disk\":  {?d}\n", .{mem.findLast(u8, line, "disk")});
    std.debug.print("findScalar ':':   {?d}\n", .{mem.findScalar(u8, line, ':')});
    std.debug.print("find \"cpu\":       {?d}\n", .{mem.find(u8, line, "cpu")});
    std.debug.print("count \"disk\":     {d}\n", .{mem.count(u8, line, "disk")});

    // Trimming returns a shorter slice of the same memory: no copy.
    const trimmed = mem.trim(u8, line, " \n");
    std.debug.print("trimmed: \"{s}\"\n", .{trimmed});
    std.debug.print("startsWith error: {}\n", .{mem.startsWith(u8, trimmed, "error")});
    std.debug.print("endsWith \")\":    {}\n", .{mem.endsWith(u8, trimmed, ")")});

    // cutPrefix: the rest after a prefix, or null.
    if (mem.cutPrefix(u8, trimmed, "error: ")) |msg| {
        std.debug.print("message: \"{s}\"\n", .{msg});
    }

    // cut: split around the first match into a 2-tuple.
    if (mem.cut(u8, "key=value=x", "=")) |kv| {
        const key, const value = kv;
        std.debug.print("key \"{s}\", value \"{s}\"\n", .{ key, value });
    }
}
