const std = @import("std");
const ascii = std.ascii;

pub fn main() void {
    std.debug.print("toLower('Q') = {c}\n", .{ascii.toLower('Q')});
    std.debug.print("isDigit('7') = {}\n", .{ascii.isDigit('7')});
    std.debug.print("eqlIgnoreCase: {}\n", .{ascii.eqlIgnoreCase("Zig", "ZIG")});
    std.debug.print("findIgnoreCase: {?d}\n", .{ascii.findIgnoreCase("The Quick Fox", "quick")});

    // lowerString writes into a buffer you provide.
    var buf: [32]u8 = undefined;
    std.debug.print("lowerString: {s}\n", .{ascii.lowerString(&buf, "Hello, WORLD")});

    // ASCII only: bytes above 127 are left alone.
    std.debug.print("eqlIgnoreCase(\"É\", \"é\"): {}\n", .{ascii.eqlIgnoreCase("É", "é")});
    std.debug.print("lowerString: {s}\n", .{ascii.lowerString(&buf, "CAFÉ")});
}
