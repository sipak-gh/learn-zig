const std = @import("std");

fn readConfig(name: []const u8) !u8 {
    if (name.len == 0) return error.NoName;
    return 1;
}

fn loadSettings() !u8 {
    return try readConfig("");
}

// Returning an error from main prints its name and the error return
// trace: every `try` it passed through.
pub fn main() !void {
    const level = try loadSettings();
    std.debug.print("level {d}\n", .{level});
}
