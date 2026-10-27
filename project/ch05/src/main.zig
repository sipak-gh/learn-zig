const std = @import("std");

const version = "0.1.0";

const exit_ok: u8 = 0; // a line matched (or nothing went wrong)
const exit_no_match: u8 = 1; // nothing matched
const exit_trouble: u8 = 2; // bad usage or an error

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

/// Mistakes in how seek was called. Keeping them in their own error set
/// separates "you called seek wrong" from "something failed while working".
const UsageError = error{ UnknownFlag, MissingPattern, MissingPath };

/// Refuse to load files larger than this into memory.
const max_file_size = 16 * 1024 * 1024;

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    // main only wires things together; `run` does the work. Usage errors
    // become exit status 2; any other error (stdout closed, ...) propagates.
    const status = run(init.io, arena, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
            try stderr.writeAll(usage);
            break :blk exit_trouble;
        },
        error.WriteFailed => return err,
    };
    try stdout.flush();
    try stderr.flush();
    return status;
}

/// Runs seek with the given command line and returns the exit status.
/// Everything it needs is passed in explicitly: no globals.
fn run(
    io: std.Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.Io.Writer.Error)!u8 {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("seek {s}\n", .{version});
            return exit_ok;
        }
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try stdout.writeAll(usage);
            return exit_ok;
        }
        // A lone "-" is not a flag; it will mean standard input later.
        if (arg.len > 1 and arg[0] == '-') {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }

    const pattern = argAt(args, 1) orelse return error.MissingPattern;
    const path = argAt(args, 2) orelse return error.MissingPath;

    // Read the whole file into memory. The arena frees it when seek exits.
    // A file we can't read is reported, not fatal: `catch` handles the error.
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size)) catch |err| {
        try stderr.print("seek: {s}: {t}\n", .{ path, err });
        return exit_trouble;
    };

    const matches = try searchText(stdout, path, pattern, contents);
    return if (matches > 0) exit_ok else exit_no_match;
}

/// Returns the argument at `index`, or null if there are not that many.
fn argAt(args: []const [:0]const u8, index: usize) ?[]const u8 {
    return if (index < args.len) args[index] else null;
}

/// Prints every line of `text` that contains `pattern` as `path:line` and
/// returns how many lines matched.
fn searchText(out: *std.Io.Writer, path: []const u8, pattern: []const u8, text: []const u8) !usize {
    // A trailing newline ends the last line; it doesn't start a new, empty one.
    const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

    var matches: usize = 0;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        if (std.mem.find(u8, line, pattern) != null) {
            try out.print("{s}:{s}\n", .{ path, line });
            matches += 1;
        }
    }
    return matches;
}
