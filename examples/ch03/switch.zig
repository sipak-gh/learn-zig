const std = @import("std");

pub fn main() void {
    for ([_]u8{ 'a', 'Z', '7', ' ', '?' }) |c| {
        // switch is an expression; every prong produces a string here.
        const kind = switch (c) {
            'a'...'z' => "lowercase", // a range, inclusive at both ends
            'A'...'Z' => "uppercase",
            '0'...'9' => "digit",
            ' ', '\t', '\n' => "whitespace", // several values
            else => "other", // everything not listed above
        };
        std.debug.print("'{c}' is {s}\n", .{ c, kind });
    }

    // Prongs can run a block of code. No fallthrough, no `break` needed.
    var status: u8 = 2;
    status += 0;
    switch (status) {
        0 => std.debug.print("matched\n", .{}),
        1 => std.debug.print("no match\n", .{}),
        2 => {
            std.debug.print("trouble\n", .{});
            std.debug.print("(status 2)\n", .{});
        },
        else => std.debug.print("unknown status\n", .{}),
    }

    // Without `else`, every possible value must be handled. A u2 has four.
    var bits: u2 = 3;
    bits += 0;
    const name = switch (bits) {
        0 => "zero",
        1 => "one",
        2 => "two",
        3 => "three",
    };
    std.debug.print("bits: {s}\n", .{name});
}
