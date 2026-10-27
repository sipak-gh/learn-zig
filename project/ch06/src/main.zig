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
    // Everything after PATTERN is a PATH. Slicing doesn't copy anything:
    // `paths` is a pointer and a length into the memory of `args`.
    const paths = args[2..];
    if (paths.len == 0) return error.MissingPath;

    var matched_any = false;
    var had_error = false;
    for (paths) |path| {
        // Read the whole file into memory. The arena frees it when seek exits.
        const contents = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(max_file_size)) catch |err| {
            // One unreadable file must not stop the search: report and go on.
            try reportError(stdout, stderr, path, err);
            had_error = true;
            continue;
        };
        if (try searchText(stdout, path, pattern, contents) > 0) matched_any = true;
    }

    if (had_error) return exit_trouble;
    return if (matched_any) exit_ok else exit_no_match;
}

/// Reports a problem with `path` on stderr. Both writers are buffered, so we
/// flush stdout first and stderr right after: that way messages appear in the
/// order things happened, even when both streams go to the same terminal.
fn reportError(stdout: *std.Io.Writer, stderr: *std.Io.Writer, path: []const u8, err: anyerror) std.Io.Writer.Error!void {
    try stdout.flush();
    try stderr.print("seek: {s}: {t}\n", .{ path, err });
    try stderr.flush();
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
