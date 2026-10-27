const std = @import("std");

pub fn main() void {
    const inputs = [_][]const u8{ "42", "-7", "0x1F", "1_000", "300", "12abc", "" };
    for (inputs) |text| {
        // Base 0 means "detect": 0x, 0o and 0b prefixes are allowed.
        if (std.fmt.parseInt(u8, text, 0)) |n| {
            std.debug.print("{s:>7} -> {d}\n", .{ text, n });
        } else |err| {
            std.debug.print("{s:>7} -> {t}\n", .{ text, err });
        }
    }

    const hex = std.fmt.parseInt(u32, "ff", 16) catch unreachable;
    std.debug.print("ff in base 16 = {d}\n", .{hex});

    const pi = std.fmt.parseFloat(f64, "3.14159") catch unreachable;
    std.debug.print("pi = {d:.2}\n", .{pi});
    if (std.fmt.parseFloat(f64, "three")) |_| {} else |err| {
        std.debug.print("three -> {t}\n", .{err});
    }
}
