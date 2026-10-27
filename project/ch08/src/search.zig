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

/// One matching line.
pub const Match = struct {
    path: []const u8,
    line_number: usize,
    text: []const u8,

    /// Writes the match in seek's output format, `path:text`.
    pub fn write(match: Match, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print("{s}:{s}\n", .{ match.path, match.text });
    }
};

/// Searches files for a pattern and remembers how it went.
///
/// Memory: the Searcher owns a copy of the pattern (allocated with `gpa`)
/// and an arena for file contents that is reset after every file, so memory
/// use stays flat no matter how many files we search. Call `deinit` to free
/// everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    file_arena: std.heap.ArenaAllocator,
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
            .file_arena = .init(gpa),
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    pub fn deinit(self: *Searcher) void {
        self.file_arena.deinit();
        self.gpa.free(self.pattern);
        self.* = undefined; // catch use-after-deinit in safe builds
    }

    /// Searches one file. Problems are reported, not returned: a file we
    /// cannot read must not stop the whole search.
    pub fn searchPath(self: *Searcher, path: []const u8) std.Io.Writer.Error!void {
        // Whatever happens below, free this file's memory (but keep the
        // arena's capacity around for the next file) when we return.
        defer _ = self.file_arena.reset(.retain_capacity);
        const arena = self.file_arena.allocator();

        const contents = std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(max_file_size)) catch |err| {
            try self.reportError(path, err);
            return;
        };
        if (try self.searchText(path, contents) > 0) self.matched_any = true;
    }

    /// Prints every line of `text` that contains the pattern and returns
    /// how many lines matched.
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
};
