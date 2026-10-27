const std = @import("std");

const Kind = enum { text, image, code };

/// Built at compile time: no allocation, nothing to free.
const by_extension: std.StaticStringMap(Kind) = .initComptime(.{
    .{ ".txt", .text },
    .{ ".md", .text },
    .{ ".png", .image },
    .{ ".jpg", .image },
    .{ ".zig", .code },
    .{ ".c", .code },
});

pub fn main(init: std.process.Init) !void {
    const files = [_][]const u8{ "notes.md", "logo.png", "main.zig", "data.bin", "notes.md" };

    // BufSet: a set of strings that copies (and later frees) each one.
    var seen: std.BufSet = .init(init.gpa);
    defer seen.deinit();

    for (files) |file| {
        if (seen.contains(file)) {
            std.debug.print("{s}: seen already\n", .{file});
            continue;
        }
        try seen.insert(file);
        const dot = std.mem.findScalarLast(u8, file, '.') orelse file.len;
        if (by_extension.get(file[dot..])) |kind| {
            std.debug.print("{s}: {t}\n", .{ file, kind });
        } else {
            std.debug.print("{s}: unknown\n", .{file});
        }
    }
    std.debug.print("{d} distinct files\n", .{seen.count()});
}
