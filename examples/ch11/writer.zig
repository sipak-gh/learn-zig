const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &buffer);
    const out = &stdout_writer.interface;

    try out.writeAll("name    score\n");
    try out.splatByteAll('-', 13);
    try out.writeByte('\n');
    for ([_][]const u8{ "ada", "linus" }, [_]u32{ 42, 7 }) |name, score| {
        try out.print("{s:<7} {d:>5}\n", .{ name, score });
    }

    // Nothing has reached stdout yet: it is all in `buffer`.
    std.debug.print("(stderr) {d} bytes buffered\n", .{out.buffered().len});
    try out.flush();

    // A fixed writer writes into an array and fails when it is full.
    var small: [8]u8 = undefined;
    var fixed: std.Io.Writer = .fixed(&small);
    fixed.writeAll("123456789") catch |err| {
        std.debug.print("(stderr) fixed: {t} after \"{s}\"\n", .{ err, fixed.buffered() });
    };
}
