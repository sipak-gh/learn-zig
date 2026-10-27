const std = @import("std");

// `?u32` is "a u32 or null". Here, null means "no digit found".
fn firstDigit(text: []const u8) ?u32 {
    for (text) |c| {
        if (c >= '0' and c <= '9') return c - '0';
    }
    return null;
}

pub fn main() void {
    const inputs = [_][]const u8{ "abc7d", "none" };
    for (inputs) |text| {
        // `if` with a capture: runs the first branch only if there's a value.
        if (firstDigit(text)) |d| {
            std.debug.print("{s}: digit {d}\n", .{ text, d });
        } else {
            std.debug.print("{s}: no digit\n", .{text});
        }

        // `orelse` supplies a default when the value is null.
        const digit = firstDigit(text) orelse 0;
        std.debug.print("{s}: digit or 0: {d}\n", .{ text, digit });
    }

    // `.?` unwraps, asserting "this is not null". It panics if it is.
    const sure = firstDigit("x9").?;
    std.debug.print("sure: {d}\n", .{sure});

    // Optionals compare with null and print as `null`.
    const missing = firstDigit("");
    std.debug.print("missing == null: {}, printed: {any}\n", .{ missing == null, missing });
}
