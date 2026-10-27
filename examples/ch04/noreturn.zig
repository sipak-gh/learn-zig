const std = @import("std");

// `noreturn` means "this function never returns to its caller".
fn fatal(message: []const u8) noreturn {
    std.debug.print("fatal: {s}\n", .{message});
    std.process.exit(2);
}

pub fn main() void {
    var config_ok = false;
    config_ok = config_ok and true; // a runtime value
    // A `noreturn` call fits anywhere a value is expected.
    const level: u8 = if (config_ok) 3 else fatal("no config");
    std.debug.print("level {d}\n", .{level});
}
