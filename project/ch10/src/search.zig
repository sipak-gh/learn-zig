//! Searching files for a pattern. Every file is a struct: this one is a
//! namespace whose `pub` declarations main.zig reaches through @import.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Refuse to load files larger than this into memory.
const max_file_size = 16 * 1024 * 1024;

/// When to highlight matches.
pub const Color = enum { auto, always, never };

/// Everything the user can configure. Every field has a default, so `.{}`
/// is a complete value. The flags arrive in Chapters 9 to 11.
pub const Options = struct {
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
/// (allocated with `gpa`), plus an arena for file contents that is reset
/// after every file, so memory use stays flat no matter how many files we
/// search. Call `deinit` to free everything.
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
        for (self.files.items) |path| self.gpa.free(path);
        self.files.deinit(self.gpa);
        self.file_arena.deinit();
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }

    /// Queues `path` for searching. The Searcher keeps its own copy.
    pub fn addPath(self: *Searcher, path: []const u8) Allocator.Error!void {
        const owned = try self.gpa.dupe(u8, path);
        // If append fails, nobody else will ever free `owned`.
        errdefer self.gpa.free(owned);
        try self.files.append(self.gpa, owned);
    }

    /// Searches every queued file, in order.
    pub fn searchAll(self: *Searcher) std.Io.Writer.Error!void {
        for (self.files.items) |path| try self.searchFile(path);
    }

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search.
    fn searchFile(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
        // Whatever happens below, free this file's memory (but keep the
        // arena's capacity around for the next file) when we return.
        defer _ = self.file_arena.reset(.retain_capacity);
        const arena = self.file_arena.allocator();

        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(max_file_size)) catch |err| {
            try self.reportError(path, err);
            return;
        };
        const matches = try self.searchText(path, contents);
        if (matches > 0) self.matched_any = true;

        // -l wins over -c, like in grep.
        if (self.options.files_only) {
            if (matches > 0) try self.stdout.print("{s}\n", .{path});
        } else if (self.options.count_only) {
            try self.stdout.print("{s}:{d}\n", .{ path, matches });
        }
    }

    /// Returns how many lines of `text` are selected, printing them unless
    /// -c or -l asked for a summary instead. A line is selected when it
    /// contains the pattern, or, with -v, when it doesn't. Stops early at the
    /// -m limit.
    fn searchText(self: *const Searcher, path: []const u8, text: []const u8) std.Io.Writer.Error!usize {
        // A trailing newline ends the last line; it doesn't start a new one.
        const body = if (std.mem.endsWith(u8, text, "\n")) text[0 .. text.len - 1] else text;

        // Inverted matches have nothing to highlight. `auto` behaves like
        // `never` until Chapter 19 teaches seek to detect a terminal.
        const highlight: ?Highlight = if (self.options.color == .always and !self.options.invert)
            .{ .pattern = self.pattern, .find = self.find }
        else
            null;

        // For -l, one selected line answers the question.
        const limit: usize = if (self.options.files_only) 1 else self.options.max_count orelse std.math.maxInt(usize);
        const print_lines = !self.options.count_only and !self.options.files_only;

        var matches: usize = 0;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = lines.next() orelse break;
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
