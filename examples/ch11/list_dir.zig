const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;
    const cwd: std.Io.Dir = .cwd();

    // Build a small tree to explore, and remove it when we are done.
    try cwd.createDirPath(io, "demo-tree/src/util");
    defer cwd.deleteTree(io, "demo-tree") catch {};
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/README.md", .data = "hi\n" });
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/src/main.zig", .data = "" });
    try cwd.writeFile(io, .{ .sub_path = "demo-tree/src/util/str.zig", .data = "" });

    // `.iterate = true` is required to list a directory's entries.
    var dir = try cwd.openDir(io, "demo-tree", .{ .iterate = true });
    defer dir.close(io);

    // One level: iterate(). Entry names are only valid until the next call.
    std.debug.print("top level:\n", .{});
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        std.debug.print("  {t:<9} {s}\n", .{ entry.kind, entry.name });
    }

    // Every level: walk(). The OS decides the order, so collect and sort.
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |p| gpa.free(p);
        paths.deinit(gpa);
    }
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        // entry.path is reused by the next call, so copy it.
        try paths.append(gpa, try gpa.dupe(u8, entry.path));
    }
    std.mem.sort([]u8, paths.items, {}, lessThan);

    std.debug.print("all files:\n", .{});
    for (paths.items) |p| std.debug.print("  {s}\n", .{p});
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}
