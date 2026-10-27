//! Searching files for a pattern. Every file is a struct: this one is a
//! namespace whose `pub` declarations main.zig reaches through @import.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const wildcardMatch = @import("match.zig").wildcardMatch;
const Options = @import("cli.zig").Options;
const Stats = @import("stats.zig").Stats;

/// Size of the buffer each file is read through. Lines longer than this
/// still work, they just take a slower path (see `nextLine`).
const read_buffer_len = 64 * 1024;

/// A file is binary if a NUL byte appears in its first 8 KiB.
const binary_probe_len = 8 * 1024;

/// ANSI escape sequences: bold red, then back to normal.
const ansi_match = "\x1b[1;31m";
const ansi_reset = "\x1b[0m";

/// A function that returns where `needle` starts in `haystack`, if anywhere.
/// `std.ascii.findIgnoreCase` already has this shape; `findExact` wraps
/// `std.mem.find` to match it.
const FindFn = *const fn (haystack: []const u8, needle: []const u8) ?usize;

fn findExact(haystack: []const u8, needle: []const u8) ?usize {
    return std.mem.find(u8, haystack, needle);
}

/// How to highlight the pattern inside a line.
pub const Highlight = struct {
    pattern: []const u8,
    find: FindFn,
};

/// One selected line, ready to print with `{f}`.
pub const Match = struct {
    path: []const u8,
    /// Null unless line numbers were requested (-n).
    line_number: ?usize,
    text: []const u8,
    /// Null means "print the text as is".
    highlight: ?Highlight = null,

    /// Called by the `{f}` format specifier: writes `path:[line:]text`.
    pub fn format(match: Match, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s}:", .{match.path});
        if (match.line_number) |n| try w.print("{d}:", .{n});
        if (match.highlight) |h| {
            try writeHighlighted(w, match.text, h);
        } else {
            try w.writeAll(match.text);
        }
    }
};

/// Writes `text`, wrapping every occurrence of the pattern in ANSI colors.
fn writeHighlighted(w: *std.Io.Writer, text: []const u8, h: Highlight) std.Io.Writer.Error!void {
    var rest = text;
    // An empty pattern matches everywhere but has nothing to color.
    while (h.pattern.len > 0) {
        const start = h.find(rest, h.pattern) orelse break;
        const end = start + h.pattern.len;
        // The format string is comptime-known, so `++` can splice in the
        // escape codes at compile time.
        try w.print("{s}" ++ ansi_match ++ "{s}" ++ ansi_reset, .{ rest[0..start], rest[start..end] });
        rest = rest[end..];
    }
    try w.writeAll(rest);
}

/// Searches files for a pattern and remembers how it went.
///
/// Use it in two phases: `addPath` for every path to search, then
/// `searchAll`.
///
/// Memory: the Searcher owns a copy of the pattern and of every path
/// (allocated with `gpa`), plus an arena for per-file scratch memory that is
/// reset after every file. Call `deinit` to free everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    /// Picked once in `init` according to -i.
    find: FindFn,
    file_arena: std.heap.ArenaAllocator,
    /// The files to search, in order. Each path is owned by the Searcher.
    files: std.ArrayList([]const u8) = .empty,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
    stats: Stats = .{},
    matched_any: bool = false,
    had_error: bool = false,

    pub fn init(
        gpa: Allocator,
        io: std.Io,
        pattern: []const u8,
        options: Options,
        stdout: *std.Io.Writer,
        stderr: *std.Io.Writer,
    ) Allocator.Error!Searcher {
        return .{
            .gpa = gpa,
            .io = io,
            // Copy the pattern so the Searcher doesn't depend on the lifetime
            // of the caller's memory.
            .pattern = try gpa.dupe(u8, pattern),
            .options = options,
            .find = if (options.ignore_case) &std.ascii.findIgnoreCase else &findExact,
            .file_arena = .init(gpa),
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    pub fn deinit(self: *Searcher) void {
        self.stats.deinit(self.gpa);
        for (self.files.items) |path| self.gpa.free(path);
        self.files.deinit(self.gpa);
        self.file_arena.deinit();
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }

    /// Queues `path` for searching: a file, "-" for standard input, or a
    /// directory, which is walked recursively.
    pub fn addPath(self: *Searcher, path: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        if (!std.mem.eql(u8, path, "-")) {
            // If stat fails we queue the path anyway: opening it later
            // reports the error, in order with the other output.
            if (Io.Dir.cwd().statFile(self.io, path, .{})) |stat| {
                if (stat.kind == .directory) return self.addDirectory(path);
            } else |_| {}
        }
        try self.addFile(try self.gpa.dupe(u8, path));
    }

    /// Takes ownership of `path` and queues it.
    fn addFile(self: *Searcher, path: []const u8) Allocator.Error!void {
        // If append fails, nobody else will ever free `path`.
        errdefer self.gpa.free(path);
        try self.files.append(self.gpa, path);
    }

    /// Queues every file below `root`, skipping hidden entries (unless
    /// --hidden) and files whose name doesn't match --glob.
    fn addDirectory(self: *Searcher, root: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        var dir = Io.Dir.cwd().openDir(self.io, root, .{ .iterate = true }) catch |err| {
            return self.reportError(root, err);
        };
        defer dir.close(self.io);

        // A selective walker only descends into directories we `enter`,
        // so hidden directories are skipped without reading them at all.
        var walker = try dir.walkSelectively(self.gpa);
        defer walker.deinit();

        const first_new = self.files.items.len;
        while (walker.next(self.io)) |maybe_entry| {
            const entry = maybe_entry orelse break;
            if (!self.options.hidden and entry.basename[0] == '.') continue;
            switch (entry.kind) {
                .directory => walker.enter(self.io, entry) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        const sub = try std.fs.path.join(self.gpa, &.{ root, entry.path });
                        defer self.gpa.free(sub);
                        try self.reportError(sub, err);
                    },
                },
                .file => {
                    if (self.options.glob) |glob| {
                        if (!wildcardMatch(glob, entry.basename)) continue;
                    }
                    // `entry.path` is relative to `root` and only valid until
                    // the next call to `next`, so we build an owned copy.
                    // Searching "." prints `poem.txt` rather than `./poem.txt`.
                    const path = if (std.mem.eql(u8, root, "."))
                        try self.gpa.dupe(u8, entry.path)
                    else
                        try std.fs.path.join(self.gpa, &.{ root, entry.path });
                    try self.addFile(path);
                },
                // Symbolic links, sockets, devices, ...: not searched.
                else => {},
            }
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => try self.reportError(root, err),
        }

        // The order a directory lists its entries in depends on the file
        // system. Sorting makes the output the same on every machine.
        std.mem.sort([]const u8, self.files.items[first_new..], {}, pathLessThan);
    }

    /// Searches every queued file, in order.
    pub fn searchAll(self: *Searcher) (Allocator.Error || Io.Writer.Error)!void {
        for (self.files.items) |path| try self.searchFile(path);
    }

    /// Searches one file ("-" is standard input). Problems are reported,
    /// not returned: a file we cannot read must not stop the whole search.
    fn searchFile(self: *Searcher, path: []const u8) (Allocator.Error || Io.Writer.Error)!void {
        // Free this file's scratch memory (keeping the capacity) on return.
        defer _ = self.file_arena.reset(.retain_capacity);

        const is_stdin = std.mem.eql(u8, path, "-");
        const file: Io.File = if (is_stdin) .stdin() else Io.Dir.cwd().openFile(self.io, path, .{}) catch |err| {
            return self.reportError(path, err);
        };
        defer if (!is_stdin) file.close(self.io);

        // Stdin may be a pipe, which can only be read front to back
        // ("streaming"); regular files can be read at any position.
        var buffer: [read_buffer_len]u8 = undefined;
        var file_reader = if (is_stdin) file.readerStreaming(self.io, &buffer) else file.reader(self.io, &buffer);
        const name = if (is_stdin) "(standard input)" else path;

        const result = self.searchReader(&file_reader.interface, name) catch |err| switch (err) {
            // The Io.Reader interface only says "read failed"; the concrete
            // File.Reader remembers why.
            error.ReadFailed => return self.reportError(path, file_reader.err.?),
            else => |e| return e,
        };
        // Binary files are skipped silently.
        const matches = result orelse return;
        if (matches > 0) self.matched_any = true;
        // `name` is either a path owned by the Searcher or a string
        // literal, so it lives as long as the stats.
        try self.stats.record(self.gpa, name, matches);

        // -l wins over -c, like in grep.
        if (self.options.files_only) {
            if (matches > 0) try self.stdout.print("{s}\n", .{name});
        } else if (self.options.count_only) {
            try self.stdout.print("{s}:{d}\n", .{ name, matches });
        }
    }

    /// Reads `reader` line by line and returns how many lines are selected,
    /// printing them unless -c or -l asked for a summary instead, or null if
    /// the input looks binary. A line is selected when it contains the
    /// pattern, or, with -v, when it doesn't. Stops early at the -m limit.
    fn searchReader(self: *Searcher, reader: *Io.Reader, path: []const u8) (error{ReadFailed} || Allocator.Error || Io.Writer.Error)!?usize {
        if (try looksBinary(reader)) return null;

        // Inverted matches have nothing to highlight. `auto` behaves like
        // `never` until Chapter 19 teaches seek to detect a terminal.
        const highlight: ?Highlight = if (self.options.color == .always and !self.options.invert)
            .{ .pattern = self.pattern, .find = self.find }
        else
            null;

        // For -l, one selected line answers the question.
        const limit: usize = if (self.options.files_only) 1 else self.options.max_count orelse std.math.maxInt(usize);
        const print_lines = !self.options.count_only and !self.options.files_only;

        var long_line: Io.Writer.Allocating = .init(self.file_arena.allocator());
        var matches: usize = 0;
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = try nextLine(reader, &long_line) orelse break;
            const found = self.find(line, self.pattern) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            if (!print_lines) continue;
            const match: Match = .{
                .path = path,
                .line_number = if (self.options.line_numbers) line_number else null,
                .text = line,
                .highlight = highlight,
            };
            try self.stdout.print("{f}\n", .{match});
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
};

fn pathLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// Peeks at the start of the input, without consuming it, and reports
/// whether it contains a NUL byte.
fn looksBinary(reader: *Io.Reader) error{ReadFailed}!bool {
    const head = reader.peek(binary_probe_len) catch |err| switch (err) {
        // A short input: everything there is is now in the buffer.
        error.EndOfStream => reader.buffered(),
        error.ReadFailed => |e| return e,
    };
    return std.mem.findScalar(u8, head, 0) != null;
}

/// Returns the next line without its '\n', or null at the end of the input.
/// Normally the line is a slice of the reader's buffer. A line that doesn't
/// fit in the buffer is copied into `long_line` instead, so no line is too
/// long to search. Either way the slice is valid until the next call.
fn nextLine(reader: *Io.Reader, long_line: *Io.Writer.Allocating) (error{ReadFailed} || Allocator.Error)!?[]const u8 {
    if (reader.takeDelimiter('\n')) |line| {
        return line;
    } else |err| switch (err) {
        error.ReadFailed => |e| return e,
        error.StreamTooLong => {},
    }
    long_line.clearRetainingCapacity();
    _ = reader.streamDelimiterEnding(&long_line.writer, '\n') catch |err| switch (err) {
        error.ReadFailed => |e| return e,
        // An Allocating writer only fails when it can't allocate.
        error.WriteFailed => return error.OutOfMemory,
    };
    // Unless the input ended, the '\n' is still buffered: skip it.
    if (reader.bufferedLen() > 0) reader.toss(1);
    return long_line.written();
}
