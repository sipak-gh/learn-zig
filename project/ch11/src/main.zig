const std = @import("std");
// A relative path imports another file of this module. The result is a
// struct type; we pull out the declarations main needs.
const search = @import("search.zig");
const Options = search.Options;
const Color = search.Color;
const Searcher = search.Searcher;

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// A multiline string literal: each line starts with `\\`. Nothing inside is
// escaped, and the last line gets no newline (hence the empty final line).
// `++` concatenates arrays at compile time.
const help = usage ++
    \\
    \\Search each PATH (default: .) for lines containing PATTERN.
    \\Directories are searched recursively; - means standard input.
    \\
    \\options:
    \\  -i            ignore case
    \\  -v            select non-matching lines
    \\  -n            show line numbers
    \\  -c            print only a count of selected lines per file
    \\  -l            print only the names of files with selected lines
    \\  -m N          stop after N selected lines per file
    \\  --hidden      search hidden files and directories
    \\  --glob GLOB   only search files whose name matches GLOB (* and ?)
    \\  --color WHEN  highlight matches: auto, always, never
    \\  -h, --help    show this help
    \\  --version     show the version
    \\
;

/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
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
const UsageError = error{ UnknownFlag, MissingValue, InvalidValue, MissingPattern };

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), init.io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    // init.gpa is a general-purpose allocator. In Debug builds it is a
    // SafeAllocator that reports leaks when main returns.
    const status = run(init.gpa, init.io, args, stdout, stderr) catch |err| switch (err) {
        error.UnknownFlag,
        error.MissingValue,
        error.InvalidValue,
        error.MissingPattern,
        => blk: {
            try stderr.writeAll(usage);
            break :blk .trouble;
        },
        error.OutOfMemory, error.WriteFailed => |e| return e,
    };
    try stdout.flush();
    try stderr.flush();
    // The enum's backing integer is the number the operating system sees.
    return @backingInt(status);
}

fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) (UsageError || std.mem.Allocator.Error || std.Io.Writer.Error)!ExitCode {
    switch (try parseArgs(args, stderr)) {
        .help => {
            try stdout.writeAll(help);
            return .ok;
        },
        .version => {
            try stdout.print("seek {s}\n", .{version});
            return .ok;
        },
        .search => |cmd| {
            var searcher: Searcher = try .init(gpa, io, cmd.pattern, cmd.options, stdout, stderr);
            defer searcher.deinit();

            for (cmd.paths) |path| try searcher.addPath(path);
            try searcher.searchAll();

            if (searcher.had_error) return .trouble;
            return if (searcher.matched_any) .ok else .no_match;
        },
    }
}

/// Turns the command line into a Command. Options come first; the first
/// argument that isn't an option is PATTERN and the rest are PATHs, so both
/// stay slices of `args`. Problems are reported on `stderr`.
fn parseArgs(args: []const [:0]const u8, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)!Command {
    var options: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        // "-" alone is a PATH (standard input, later), not an option.
        if (arg.len < 2 or arg[0] != '-') break;
        // "--" ends the options, so `seek -- -v` searches for "-v".
        if (eql(arg, "--")) {
            i += 1;
            break;
        }
        if (eql(arg, "--version")) return .version;
        if (eql(arg, "-h") or eql(arg, "--help")) return .help;

        if (eql(arg, "-i")) {
            options.ignore_case = true;
        } else if (eql(arg, "-v")) {
            options.invert = true;
        } else if (eql(arg, "-n")) {
            options.line_numbers = true;
        } else if (eql(arg, "-c")) {
            options.count_only = true;
        } else if (eql(arg, "-l")) {
            options.files_only = true;
        } else if (eql(arg, "-m")) {
            const value = try takeValue(args, &i, stderr);
            options.max_count = std.fmt.parseInt(usize, value, 10) catch {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else if (eql(arg, "--hidden")) {
            options.hidden = true;
        } else if (eql(arg, "--glob")) {
            options.glob = try takeValue(args, &i, stderr);
        } else if (eql(arg, "--color")) {
            const value = try takeValue(args, &i, stderr);
            // Turn "always" into Color.always; null if no tag has that name.
            options.color = std.meta.stringToEnum(Color, value) orelse {
                try stderr.print("seek: invalid value '{s}' for {s}\n", .{ value, arg });
                return error.InvalidValue;
            };
        } else {
            try stderr.print("seek: unknown flag '{s}'\n", .{arg});
            return error.UnknownFlag;
        }
    }
    if (i >= args.len) return error.MissingPattern;
    const paths = args[i + 1 ..];
    return .{
        .search = .{
            .options = options,
            .pattern = args[i],
            // No PATH means the current directory.
            .paths = if (paths.len > 0) paths else &.{"."},
        },
    };
}

/// Returns the value that follows the flag at `args[i.*]` and advances `i`
/// past it. Takes a pointer so it can move the caller's loop index.
fn takeValue(args: []const [:0]const u8, i: *usize, stderr: *std.Io.Writer) (UsageError || std.Io.Writer.Error)![]const u8 {
    const flag = args[i.*];
    i.* += 1;
    return argAt(args, i.*) orelse {
        try stderr.print("seek: {s} needs a value\n", .{flag});
        return error.MissingValue;
    };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn argAt(args: []const [:0]const u8, index: usize) ?[]const u8 {
    return if (index < args.len) args[index] else null;
}
