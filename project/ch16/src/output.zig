//! Writing results. Search code reports what it found to a `Printer`; the
//! printer decides what that looks like.

const std = @import("std");
const Io = std.Io;
const Matcher = @import("match.zig").Matcher;
const Options = @import("cli.zig").Options;

/// ANSI escape sequences: bold red, then back to normal.
const ansi_match = "\x1b[1;31m";
const ansi_reset = "\x1b[0m";

/// The output modes, as a tagged union: a value is exactly one of them,
/// and each carries only the data it needs.
pub const Printer = union(enum) {
    /// Print every selected line (the default).
    lines: Lines,
    /// -c: print `path:count` for every file.
    count,
    /// -l: print the names of files with a selected line.
    files,

    pub const Lines = struct {
        line_numbers: bool,
        /// Null means "print lines without color".
        highlight: ?Matcher,
    };

    pub fn init(options: Options, matcher: Matcher) Printer {
        // -l wins over -c, like in grep.
        if (options.files_only) return .files;
        if (options.count_only) return .count;
        return .{
            .lines = .{
                .line_numbers = options.line_numbers,
                // Inverted matches have nothing to highlight. `auto` behaves like
                // `never` until Chapter 19 teaches seek to detect a terminal.
                .highlight = if (options.color == .always and !options.invert) matcher else null,
            },
        };
    }

    /// Called for every selected line.
    pub fn line(printer: Printer, w: *Io.Writer, path: []const u8, line_number: usize, text: []const u8) Io.Writer.Error!void {
        switch (printer) {
            .lines => |lines| {
                const match: Match = .{
                    .path = path,
                    .line_number = if (lines.line_numbers) line_number else null,
                    .text = text,
                    .highlight = lines.highlight,
                };
                try w.print("{f}\n", .{match});
            },
            .count, .files => {},
        }
    }

    /// Called once a file has been searched, with its number of selected lines.
    pub fn fileDone(printer: Printer, w: *Io.Writer, path: []const u8, matches: usize) Io.Writer.Error!void {
        switch (printer) {
            .lines => {},
            .count => try w.print("{s}:{d}\n", .{ path, matches }),
            .files => if (matches > 0) try w.print("{s}\n", .{path}),
        }
    }
};

/// One selected line, ready to print with `{f}`.
pub const Match = struct {
    path: []const u8,
    /// Null unless line numbers were requested (-n).
    line_number: ?usize,
    text: []const u8,
    /// Null means "print the text as is".
    highlight: ?Matcher = null,

    /// Called by the `{f}` format specifier: writes `path:[line:]text`.
    pub fn format(match: Match, w: *Io.Writer) Io.Writer.Error!void {
        try w.print("{s}:", .{match.path});
        if (match.line_number) |n| try w.print("{d}:", .{n});
        if (match.highlight) |matcher| {
            try writeHighlighted(w, match.text, matcher);
        } else {
            try w.writeAll(match.text);
        }
    }
};

/// Writes `text`, wrapping every match in ANSI colors.
fn writeHighlighted(w: *Io.Writer, text: []const u8, matcher: Matcher) Io.Writer.Error!void {
    var rest = text;
    while (matcher.find(rest)) |span| {
        // An empty match (an empty pattern, or `-W '*'` on an empty line)
        // has nothing to color, and searching again would find it forever.
        if (span.end == span.start) break;
        // The format string is comptime-known, so `++` can splice in the
        // escape codes at compile time.
        try w.print("{s}" ++ ansi_match ++ "{s}" ++ ansi_reset, .{ rest[0..span.start], rest[span.start..span.end] });
        rest = rest[span.end..];
    }
    try w.writeAll(rest);
}

const testing = std.testing;

test "Printer.lines prints every line" {
    // A fixed writer writes into a buffer we provide: no allocation.
    var buffer: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    const printer: Printer = .init(.{ .line_numbers = true }, .init("fox", false, false));
    try printer.line(&w, "a.txt", 3, "the fox");
    try printer.line(&w, "a.txt", 7, "a fox");
    try printer.fileDone(&w, "a.txt", 2);
    try testing.expectEqualStrings("a.txt:3:the fox\na.txt:7:a fox\n", w.buffered());
}

test "Printer.count and Printer.files summarize each file" {
    var buffer: [128]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    const matcher: Matcher = .init("fox", false, false);

    const count: Printer = .init(.{ .count_only = true }, matcher);
    try count.line(&w, "a.txt", 1, "the fox");
    try count.fileDone(&w, "a.txt", 1);
    try count.fileDone(&w, "b.txt", 0);

    // -l wins over -c.
    const files: Printer = .init(.{ .count_only = true, .files_only = true }, matcher);
    try testing.expect(files == .files);
    try files.fileDone(&w, "a.txt", 1);
    try files.fileDone(&w, "b.txt", 0);

    try testing.expectEqualStrings("a.txt:1\nb.txt:0\na.txt\n", w.buffered());
}

test "Match highlights every occurrence" {
    const match: Match = .{
        .path = "p",
        .line_number = null,
        .text = "fox and fox",
        .highlight = .init("fox", false, false),
    };
    try testing.expectFmt("p:" ++ ansi_match ++ "fox" ++ ansi_reset ++ " and " ++
        ansi_match ++ "fox" ++ ansi_reset, "{f}", .{match});
}

test "Match does not loop on empty matches" {
    const match: Match = .{
        .path = "p",
        .line_number = 1,
        .text = "",
        .highlight = .init("*", false, true),
    };
    try testing.expectFmt("p:1:", "{f}", .{match});
}
