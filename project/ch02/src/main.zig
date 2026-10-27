const std = @import("std");

/// The version of seek. A file-scope `const` is known at compile time and
/// costs nothing at run time; its type is inferred from the string literal.
const version = "0.1.0";

// Exit statuses, following grep's convention. Each has an explicit type:
// `u8` is what the operating system expects for an exit status.
const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("seek {s}\n", .{version});
    try stdout.print("usage: seek [OPTIONS] PATTERN [PATH ...]\n", .{});
    try stdout.print("exit status: {d} = match, {d} = no match, {d} = trouble\n", .{
        exit_ok,
        exit_no_match,
        exit_trouble,
    });
    try stdout.flush();
}
