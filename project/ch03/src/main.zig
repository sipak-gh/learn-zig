const std = @import("std");

const version = "0.1.0";

const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// Returning `u8` from main sets the process exit status.
pub fn main(init: std.process.Init) !u8 {
    // The arena lives as long as the process, so it is a good home for the
    // argument list. args[0] is the program name.
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    // --version and --help win wherever they appear on the command line.
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("seek {s}\n", .{version});
            try stdout.flush();
            return exit_ok;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            try stdout.flush();
            return exit_ok;
        }
    }

    // Without a PATTERN there is nothing to do: complain on stderr.
    if (args.len < 2) {
        try stderr.writeAll(usage);
        try stderr.flush();
        return exit_trouble;
    }

    const pattern = args[1];
    try stdout.print("pattern: {s}\n", .{pattern});
    for (args[2..], 1..) |path, n| {
        try stdout.print("path {d}: {s}\n", .{ n, path });
    }
    try stdout.flush();
    return exit_no_match; // we don't search yet, so nothing can match
}
