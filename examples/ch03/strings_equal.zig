const std = @import("std");

pub fn main() void {
    const flags = [_][]const u8{ "--help", "-v", "--version", "--color" };
    for (flags) |flag| {
        // Strings are compared byte by byte with std.mem.eql, not `==`.
        if (std.mem.eql(u8, flag, "--help") or std.mem.eql(u8, flag, "-h")) {
            std.debug.print("{s}: show help\n", .{flag});
        } else if (std.mem.eql(u8, flag, "--version")) {
            std.debug.print("{s}: show version\n", .{flag});
        } else {
            std.debug.print("{s}: unknown\n", .{flag});
        }
    }
}
