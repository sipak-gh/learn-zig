const std = @import("std");
const builtin = @import("builtin");

// A comptime `if` on a comptime-known condition: the other branch is not
// even compiled, so it may use APIs that don't exist on this platform.
const line_ending = if (builtin.os.tag == .windows) "\r\n" else "\n";

pub fn main() void {
    std.debug.print("os: {t}, arch: {t}, mode: {t}\n", .{
        builtin.os.tag,
        builtin.cpu.arch,
        builtin.mode,
    });
    std.debug.print("line ending: {d} byte(s)\n", .{line_ending.len});

    if (builtin.mode == .debug) {
        std.debug.print("debug build: safety checks are on\n", .{});
    } else {
        std.debug.print("release build\n", .{});
    }
}
