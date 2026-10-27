const std = @import("std");

// An error set lists the errors a function can return.
const ParseError = error{ Empty, BadDigit };

// `ParseError!u8` is an error union: a u8 or one of the errors in ParseError.
fn parseDigit(text: []const u8) ParseError!u8 {
    if (text.len == 0) return error.Empty;
    const c = text[0];
    if (c < '0' or c > '9') return error.BadDigit;
    return c - '0';
}

// `try x` means `x catch |err| return err`: pass errors up to the caller.
fn sumOfFirstDigits(a: []const u8, b: []const u8) ParseError!u8 {
    const x = try parseDigit(a);
    const y = try parseDigit(b);
    return x + y;
}

pub fn main() void {
    // `catch` with a value: use a default on any error.
    const d = parseDigit("x") catch 0;
    std.debug.print("with default: {d}\n", .{d});

    // `catch |err| switch`: handle each error separately.
    for ([_][]const u8{ "7", "", "?" }) |text| {
        const value = parseDigit(text) catch |err| switch (err) {
            error.Empty => {
                std.debug.print("'{s}': empty input\n", .{text});
                continue;
            },
            error.BadDigit => {
                std.debug.print("'{s}': not a digit\n", .{text});
                continue;
            },
        };
        std.debug.print("'{s}': {d}\n", .{ text, value });
    }

    // `if` with an error union: the else branch captures the error.
    if (sumOfFirstDigits("4", "5")) |sum| {
        std.debug.print("sum: {d}\n", .{sum});
    } else |err| {
        std.debug.print("failed: {t}\n", .{err});
    }

    // {t} and @errorName both give an error's name.
    const err: ParseError = error.BadDigit;
    std.debug.print("{t} / {s}\n", .{ err, @errorName(err) });
}
