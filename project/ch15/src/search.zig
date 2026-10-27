//! Searching files for a pattern. Every file is a struct: this one is a
//! namespace whose `pub` declarations main.zig reaches through @import.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const match = @import("match.zig");
const Matcher = match.Matcher;
const Printer = @import("output.zig").Printer;
const Options = @import("cli.zig").Options;
const Stats = @import("stats.zig").Stats;

/// Size of the buffer each file is read through. Lines longer than this
/// still work, they just take a slower path (see `nextLine`).
const read_buffer_len = 64 * 1024;

/// A file is binary if a NUL byte appears in its first 8 KiB.
const binary_probe_len = 8 * 1024;

/// What searching one file produced. A worker fills it in, then sets
/// `done`; the main thread waits for `done` before reading anything else.
const FileResult = struct {
    /// Everything the printer wrote for this file.
    output: Io.Writer.Allocating,
    /// Selected lines; null for a binary file or after an error.
    matches: ?usize = null,
    err: ?anyerror = null,
    done: Io.Event = .unset,
};

/// Searches files for a pattern and remembers how it went.
///
/// Use it in two phases: `addPath` for every path to search, then
/// `searchAll`.
///
/// `searchAll` searches up to `jobs` files at once but prints the results
/// in the order the files were added.
///
/// Memory: the Searcher owns a copy of the pattern and of every path
/// (allocated with `gpa`). Call `deinit` to free everything.
pub const Searcher = struct {
    gpa: Allocator,
    io: std.Io,
    pattern: []const u8,
    options: Options,
    /// Decides whether a line matches; refers to `pattern`.
    matcher: Matcher,
    printer: Printer,
    /// How many files to search at the same time (-j).
    jobs: usize,
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
        // Copy the pattern so the Searcher doesn't depend on the lifetime
        // of the caller's memory.
        const owned_pattern = try gpa.dupe(u8, pattern);
        const matcher: Matcher = .init(owned_pattern, options.ignore_case, options.wildcard);
        return .{
            .gpa = gpa,
            .io = io,
            .pattern = owned_pattern,
            .options = options,
            .matcher = matcher,
            .printer = .init(options, matcher),
            // By default, one worker per CPU. `-j 0` would mean "no workers",
            // so we treat it like `-j 1`.
            .jobs = @max(1, options.jobs orelse std.Thread.getCpuCount() catch 1),
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    pub fn deinit(self: *Searcher) void {
        self.stats.deinit(self.gpa);
        for (self.files.items) |path| self.gpa.free(path);
        self.files.deinit(self.gpa);
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
                        if (!match.wildcardMatch(glob, entry.basename)) continue;
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

    /// Searches every queued file and prints the results in order.
    ///
    /// Workers take the next file index from a shared atomic counter and
    /// write each file's output into that file's own `FileResult`. This
    /// thread waits for the results one by one, in order, and prints them,
    /// so the output is the same no matter which worker finishes first.
    pub fn searchAll(self: *Searcher) (Allocator.Error || Io.Writer.Error)!void {
        const files = self.files.items;
        const results = try self.gpa.alloc(FileResult, files.len);
        defer self.gpa.free(results);
        for (results) |*result| result.* = .{ .output = .init(self.gpa) };
        defer for (results) |*result| result.output.deinit();

        var next_index: std.atomic.Value(usize) = .init(0);
        var group: Io.Group = .init;
        // If printing fails we return early while workers are still
        // running. `cancel` asks them to stop and waits until they have, so
        // none of them can touch `results` after it is freed. (Defers run
        // in reverse order: this one runs first.) On success, the workers
        // are finishing anyway.
        defer group.cancel(self.io);

        var started: usize = 0;
        for (0..@min(self.jobs, files.len)) |_| {
            // `concurrent` fails with error.ConcurrencyUnavailable if no
            // thread can be started; fewer workers is fine.
            group.concurrent(self.io, worker, .{ self, results, &next_index }) catch break;
            started += 1;
        }
        // No workers at all: search everything on this thread first.
        if (started == 0) worker(self, results, &next_index);

        for (files, results) |path, *result| {
            // Not a cancelation point: nobody cancels the main thread.
            result.done.waitUncancelable(self.io);
            try self.stdout.writeAll(result.output.written());
            // Free this file's output now instead of at the end.
            result.output.deinit();
            result.output = .init(self.gpa);

            if (result.err) |err| switch (err) {
                // The output is an Allocating writer: it only fails when
                // it runs out of memory.
                error.OutOfMemory, error.WriteFailed => return error.OutOfMemory,
                else => try self.reportError(path, err),
            };
            // Binary files (null) are skipped silently.
            const matches = result.matches orelse continue;
            if (matches > 0) self.matched_any = true;
            // Only this thread touches the stats, so they need no locking.
            try self.stats.record(self.gpa, displayName(path), matches);
        }
    }

    /// Runs on a worker thread until no files are left. Many workers share
    /// one Searcher, so they only read from it (`*const`), and each has
    /// its own scratch arena: resetting an arena is not thread-safe.
    fn worker(self: *const Searcher, results: []FileResult, next_index: *std.atomic.Value(usize)) void {
        var arena: std.heap.ArenaAllocator = .init(self.gpa);
        defer arena.deinit();
        while (true) {
            // Adds 1 and returns the old value in one indivisible step, so
            // no two workers ever get the same index. `.monotonic` is
            // enough: the counter only hands out numbers, it doesn't
            // publish any other data.
            const i = next_index.fetchAdd(1, .monotonic);
            if (i >= results.len) return;

            const result = &results[i];
            if (self.searchFile(self.files.items[i], &result.output.writer, arena.allocator())) |matches| {
                result.matches = matches;
            } else |err| {
                // seek is shutting down (see `group.cancel` in searchAll).
                if (err == error.Canceled) return;
                result.err = err;
            }
            _ = arena.reset(.retain_capacity);
            // `set` publishes everything written to `result` above: after
            // `wait` returns, the main thread is guaranteed to see it.
            result.done.set(self.io);
        }
    }

    /// Searches one file ("-" is standard input), writing to `out`. Returns
    /// the number of selected lines, or null for a binary file.
    fn searchFile(self: *const Searcher, path: []const u8, out: *Io.Writer, arena: Allocator) !?usize {
        const is_stdin = std.mem.eql(u8, path, "-");
        const file: Io.File = if (is_stdin) .stdin() else try Io.Dir.cwd().openFile(self.io, path, .{});
        defer if (!is_stdin) file.close(self.io);

        // Stdin may be a pipe, which can only be read front to back
        // ("streaming"); regular files can be read at any position. The
        // buffer lives on this worker's stack.
        var buffer: [read_buffer_len]u8 = undefined;
        var file_reader = if (is_stdin) file.readerStreaming(self.io, &buffer) else file.reader(self.io, &buffer);

        return self.searchReader(&file_reader.interface, displayName(path), out, arena) catch |err| switch (err) {
            // The Io.Reader interface only says "read failed"; the concrete
            // File.Reader remembers why.
            error.ReadFailed => file_reader.err.?,
            else => |e| e,
        };
    }

    /// Reads `reader` line by line, hands every selected line to the
    /// printer, and returns how many lines were selected, or null if the
    /// input looks binary. A line is selected when it matches, or, with -v,
    /// when it doesn't. Stops early at the -m limit. `arena` holds lines
    /// too long for the reader's buffer.
    fn searchReader(
        self: *const Searcher,
        reader: *Io.Reader,
        path: []const u8,
        out: *Io.Writer,
        arena: Allocator,
    ) (error{ReadFailed} || Allocator.Error || Io.Writer.Error)!?usize {
        if (try looksBinary(reader)) return null;

        // For -l, one selected line answers the question. Comparing a
        // tagged union with an enum literal compares the active tag.
        const limit: usize = if (self.printer == .files) 1 else self.options.max_count orelse std.math.maxInt(usize);

        var long_line: Io.Writer.Allocating = .init(arena);
        var matches: usize = 0;
        var line_number: usize = 1;
        while (matches < limit) : (line_number += 1) {
            const line = try nextLine(reader, &long_line) orelse break;
            const found = self.matcher.find(line) != null;
            if (found == self.options.invert) continue;
            matches += 1;
            try self.printer.line(out, path, line_number, line);
        }
        try self.printer.fileDone(out, path, matches);
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

/// How a path appears in the output.
fn displayName(path: []const u8) []const u8 {
    return if (std.mem.eql(u8, path, "-")) "(standard input)" else path;
}

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
