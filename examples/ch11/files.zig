const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const cwd: std.Io.Dir = .cwd();

    // Create (or truncate) a file and write all of `data` to it.
    try cwd.writeFile(io, .{ .sub_path = "hello.txt", .data = "hello\nworld\n" });
    // Registered first, so it runs last: after `file.close` below.
    defer cwd.deleteFile(io, "hello.txt") catch {};

    // Open the file and ask the OS about it.
    const file = try cwd.openFile(io, "hello.txt", .{});
    defer file.close(io);
    const stat = try file.stat(io);
    std.debug.print("kind: {t}, size: {d} bytes\n", .{ stat.kind, stat.size });

    // Read a whole file into memory. We own the result and must free it.
    const contents = try cwd.readFileAlloc(io, "hello.txt", gpa, .limited(1024 * 1024));
    defer gpa.free(contents);
    std.debug.print("contents: \"{f}\"\n", .{std.zig.fmtString(contents)});

    // A missing file is an ordinary error value.
    if (cwd.openFile(io, "missing.txt", .{})) |f| {
        f.close(io);
    } else |err| {
        std.debug.print("missing.txt: {t}\n", .{err});
    }

    // The limit protects you from loading a huge file by accident.
    _ = cwd.readFileAlloc(io, "hello.txt", gpa, .limited(4)) catch |err| {
        std.debug.print("with a 4-byte limit: {t}\n", .{err});
    };
}
