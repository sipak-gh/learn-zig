const std = @import("std");

const ReadError = error{ NotFound, AccessDenied };
const ParseError = error{ Empty, BadDigit };

// `||` merges two error sets.
const LoadError = ReadError || ParseError;

fn read(name: []const u8) ReadError![]const u8 {
    if (std.mem.eql(u8, name, "secret")) return error.AccessDenied;
    if (std.mem.eql(u8, name, "missing")) return error.NotFound;
    return "7";
}

fn parse(text: []const u8) ParseError!u8 {
    if (text.len == 0) return error.Empty;
    if (text[0] < '0' or text[0] > '9') return error.BadDigit;
    return text[0] - '0';
}

// Both functions' errors fit in LoadError, so `try` works on each.
fn load(name: []const u8) LoadError!u8 {
    return try parse(try read(name));
}

// With `!u8` and no set, the compiler infers the set from the body.
fn loadTwice(name: []const u8) !u8 {
    return try load(name) * 2;
}

pub fn main() void {
    for ([_][]const u8{ "config", "secret", "missing" }) |name| {
        if (loadTwice(name)) |v| {
            std.debug.print("{s}: {d}\n", .{ name, v });
        } else |err| {
            std.debug.print("{s}: error.{t}\n", .{ name, err });
        }
    }

    // Every error set coerces to `anyerror`, the set of all errors.
    const any: anyerror = error.NotFound;
    std.debug.print("anyerror holds: {t}\n", .{any});
}
