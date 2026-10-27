const std = @import("std");
const cli = @import("cli.zig");
const Options = cli.Options;
const Searcher = @import("search.zig").Searcher;

const version = "0.1.0";

const usage = "usage: seek [OPTIONS] PATTERN [PATH ...]\n";

// cli.help runs at compile time, so `help` is one constant string.
const help = usage ++
    \\
    \\Search each PATH (default: .) for lines containing PATTERN.
    \\Directories are searched recursively; - means standard input.
    \\
    \\options:
    \\
++ cli.help(Options);

/// The process exit status. An explicit tag type (`u8`) fixes each value.
const ExitCode = enum(u8) {
    ok = 0, // a line matched (or nothing went wrong)
    no_match = 1, // nothing matched
    trouble = 2, // bad usage or an error
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

    const status = run(init.gpa, init.io, args[1..], stdout, stderr) catch |err| switch (err) {
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
    return @backingInt(status);
}

/// Runs seek with the arguments after the program name.
fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    args: []const [:0]const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !ExitCode {
    var diag: cli.Diagnostic = .{};
    const options, const positionals = cli.parse(Options, gpa, args, &diag) catch |err| {
        switch (err) {
            error.UnknownFlag => try stderr.print("seek: unknown flag '{s}'\n", .{diag.flag}),
            error.MissingValue => try stderr.print("seek: {s} needs a value\n", .{diag.flag}),
            error.InvalidValue => try stderr.print("seek: invalid value '{s}' for {s}\n", .{ diag.value, diag.flag }),
            error.OutOfMemory => {},
        }
        return err;
    };
    defer gpa.free(positionals);

    if (options.help) {
        try stdout.writeAll(help);
        return .ok;
    }
    if (options.version) {
        try stdout.print("seek {s}\n", .{version});
        return .ok;
    }
    if (positionals.len == 0) return error.MissingPattern;
    const pattern = positionals[0];
    // No PATH means the current directory.
    const default_paths: []const []const u8 = &.{"."};
    const paths = if (positionals.len > 1) positionals[1..] else default_paths;

    var searcher: Searcher = try .init(gpa, io, pattern, options, stdout, stderr);
    defer searcher.deinit();

    for (paths) |path| try searcher.addPath(path);
    try searcher.searchAll();

    if (searcher.had_error) return .trouble;
    return if (searcher.matched_any) .ok else .no_match;
}
