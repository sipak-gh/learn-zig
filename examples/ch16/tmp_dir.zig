const std = @import("std");
const testing = std.testing;
const Io = std.Io;

/// Counts the lines of the file at `path` in `dir`.
fn countLines(io: Io, dir: Io.Dir, path: []const u8) !usize {
    var buffer: [256]u8 = undefined;
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &buffer);
    var lines: usize = 0;
    while (try file_reader.interface.takeDelimiter('\n')) |_| lines += 1;
    return lines;
}

test "countLines" {
    const io = testing.io; // an Io for tests
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup(); // deletes the directory and everything in it

    try tmp.dir.createDirPath(io, "sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "sub/three.txt", .data = "a\nb\nc\n" });
    try testing.expectEqual(3, try countLines(io, tmp.dir, "sub/three.txt"));
    try testing.expectError(error.FileNotFound, countLines(io, tmp.dir, "nope.txt"));
}
