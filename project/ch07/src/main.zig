const std = @import("std");

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

/// Refuse to load files larger than this into memory.
const max_file_size = 16 * 1024 * 1024;

/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
};

/// When to highlight matches.
const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. The flags arrive in Chapters 9 to 11.
const Options = struct {
    ignore_case: bool = false, // -i
    invert: bool = false, // -v
    line_numbers: bool = false, // -n
    count_only: bool = false, // -c
    files_only: bool = false, // -l
    max_count: ?usize = null, // -m N
    hidden: bool = false, // --hidden
    glob: ?[]const u8 = null, // --glob GLOB
    color: Color = .auto, // --color WHEN
};

/// What the command line asks seek to do: a tagged union, so each case
/// carries exactly the data it needs.
const Command = union(enum) {
    help,
    version,
    search: Search,

    const Search = struct {
        options: Options = .{},
        pattern: []const u8,
        paths: []const [:0]const u8,
    };
};

/// Mistakes in how seek was called.
const UsageError = error{ UnknownFlag, MissingPattern, MissingPath };

/// One matching line.
const Match = struct {
    path: []const u8,
    line_number: usize,
    text: []const u8,

    /// Writes the match in seek's output format, `path:text`.
    fn write(match: Match, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{s}:{s}\n", .{ match.path, match.text });
    }
};

/// Searches files for a pattern and remembers how it went.
const Searcher = struct {
    io: std.Io,
    arena: std.mem.Allocator,
    pattern: []const u8,
    options: Options,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    matched_any: bool = false,
    had_error: bool = false,

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search. `self` is a pointer
    /// because this method updates `matched_any` and `had_error`.
    fn searchPath(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, path, self.arena, .limited(max_file_size)) catch |err| {
            try self.reportError(path, err);
            return;
        };
        if (try self.searchText(path, contents) > 0) self.matched_any = true;
    }

    /// Prints every line of `text` that contains the pattern and returns
    /// how many lines matched. Only reads `self`, so it takes a const pointer.
    fn searchText(self: *const Searcher, path: []const u8, text: []const u8) std.Io.Writer.Error!usize {
        // A trailing newline ends the last line; it doesn't start a new one.
        const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

        var matches: usize = 0;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var line_number: usize = 1;
        while (lines.next()) |line| : (line_number += 1) {
            if (std.mem.find(u8, line, self.pattern) == null) continue;
            const match: Match = .{ .path = path, .line_number = line_number, .text = line };
            try match.write(self.stdout);
            matches += 1;
        }
        return matches;
    }

    /// Reports a problem with `path` on stderr, flushing stdout first so the
    /// two streams interleave in the order things happened.
    fn reportError(self: *Searcher, path: []const u8, err: anyerror) std.Io.Writer.Error!void {
        self.had_error = true;
        try self.stdout.flush();
        try self.stderr.print("seek: {s}: {t}\n", .{ path, err });
        try self.stderr.flush();
    }

    fn exitCode(self: Searcher) ExitCode {
        if (self.had_error) return .trouble;
        return if (self.matched_any) .ok else .no_match;
    }
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    const status = run(init.io, arena, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.WriteFailed => return err,
    };
    try stdout.flush();
    try stderr.flush();
    // The enum's backing integer is the number the operating system sees.
    return @backingInt(status);
}

fn run(
    io: std.Io,
    arena: std.mem.Allocator,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.Io.Writer.Error)!ExitCode {
    switch (try parseArgs(args, stderr)) {
        .help => {
            try stdout.writeAll(usage);
            return .ok;
        },
        .version => {
            try stdout.print("seek {s}\n", .{version});
            return .ok;
        },
        .search => |search| {
            var searcher: Searcher = .{
                .io = io,
                .arena = arena,
                .pattern = search.pattern,
                .options = search.options,
                .stdout = stdout,
                .stderr = stderr,
            };
            for (search.paths) |path| try searcher.searchPath(path);
            return searcher.exitCode();
        },
    }
}

/// Turns the command line into a Command. Unknown flags are reported on
/// `stderr` so the user sees which one was wrong.
fn parseArgs(args: []const [:0]const u8, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)!Command {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) return .version;
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) return .help;
        if (arg.len > 1 and arg[0] == '-') {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }
    if (args.len < 2) return error.MissingPattern;
    if (args.len < 3) return error.MissingPath;
    return .{ .search = .{ .pattern = args[1], .paths = args[2..] } };
}
