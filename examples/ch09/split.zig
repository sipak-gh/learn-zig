const std = @import("std");
const mem = std.mem;

pub fn main() void {
    const csv = "a,b,,c";

    // splitScalar: every separator splits, so empty fields appear.
    var fields = mem.splitScalar(u8, csv, ',');
    std.debug.print("split:   ", .{});
    while (fields.next()) |f| std.debug.print("[{s}]", .{f});
    std.debug.print("\n", .{});

    // tokenizeScalar: runs of separators are skipped, no empty tokens.
    var tokens = mem.tokenizeScalar(u8, csv, ',');
    std.debug.print("tokenize:", .{});
    while (tokens.next()) |t| std.debug.print("[{s}]", .{t});
    std.debug.print("\n", .{});

    // tokenizeAny: any of several separator bytes.
    var words = mem.tokenizeAny(u8, "  one two\tthree\n", " \t\n");
    std.debug.print("words:   ", .{});
    while (words.next()) |w| std.debug.print("[{s}]", .{w});
    std.debug.print("\n", .{});

    // splitSequence: the separator is a whole string.
    var parts = mem.splitSequence(u8, "one :: two :: three", " :: ");
    std.debug.print("parts:   ", .{});
    while (parts.next()) |p| std.debug.print("[{s}]", .{p});
    std.debug.print("\n", .{});

    // The iterator can also give you the unsplit rest.
    var it = mem.splitScalar(u8, "cmd arg1 arg2", ' ');
    const cmd = it.first();
    std.debug.print("cmd [{s}], rest [{s}]\n", .{ cmd, it.rest() });
}
