const std = @import("std");
// A relative path imports another file of this module. The result is a
// struct type; we pull out the declarations main needs.
const search = @import("search.zig");
const Options = search.Options;
const Searcher = search.Searcher;

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

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
const UsageError = error{ UnknownFlag, MissingPattern, MissingPath };

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
        error.UnknownFlag, error.MissingPattern, error.MissingPath => blk: {
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
            try stdout.writeAll(usage);
            return .ok;
        },
        .version => {
            try stdout.print("seek {s}\n", .{version});
            return .ok;
        },
        .search => |cmd| {
            var searcher: Searcher = try .init(gpa, io, cmd.pattern, cmd.options, stdout, stderr);
            defer searcher.deinit();

            for (cmd.paths) |path| try searcher.searchPath(path);

            if (searcher.had_error) return .trouble;
            return if (searcher.matched_any) .ok else .no_match;
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
