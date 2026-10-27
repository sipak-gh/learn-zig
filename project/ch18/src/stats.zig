//! Statistics for --stats, built on a generic counter.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Returns a type that counts how often each key of type `K` was seen.
///
/// Strings need a different hash map than numbers: `AutoHashMap` refuses
/// slices (should it hash the pointer or the bytes?), so for `[]const u8`
/// we pick `StringHashMap`, which hashes the bytes. The choice happens at
/// compile time; each `Counter(K)` contains only the code it needs.
///
/// Keys are not copied: they must outlive the counter.
pub fn Counter(comptime K: type) type {
    const is_string = K == []const u8;
    if (!is_string and @typeInfo(K) != .int) {
        @compileError("Counter: keys must be integers or []const u8, not " ++ @typeName(K));
    }
    const Map = if (is_string)
        std.StringHashMapUnmanaged(usize)
    else
        std.AutoHashMapUnmanaged(K, usize);

    return struct {
        // Inside the anonymous struct, @This() is the only way to name it.
        const Self = @This();

        pub const Entry = struct { key: K, count: usize };

        map: Map = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.map.deinit(gpa);
            self.* = undefined;
        }

        /// Adds `n` to the count for `key`.
        pub fn add(self: *Self, gpa: Allocator, key: K, n: usize) Allocator.Error!void {
            const result = try self.map.getOrPut(gpa, key);
            if (!result.found_existing) result.value_ptr.* = 0;
            result.value_ptr.* += n;
        }

        /// Returns the count for `key` (zero if it was never added).
        pub fn get(self: Self, key: K) usize {
            return self.map.get(key) orelse 0;
        }

        /// Returns at most `n` entries, highest count first. Equal counts
        /// are ordered by key, so the result never depends on the order of
        /// the hash map. The caller owns the returned slice.
        pub fn topN(self: Self, gpa: Allocator, n: usize) Allocator.Error![]Entry {
            var entries: std.ArrayList(Entry) = try .initCapacity(gpa, self.map.count());
            errdefer entries.deinit(gpa);
            var it = self.map.iterator();
            while (it.next()) |kv| {
                entries.appendAssumeCapacity(.{ .key = kv.key_ptr.*, .count = kv.value_ptr.* });
            }
            std.mem.sort(Entry, entries.items, {}, entryLessThan);
            entries.shrinkRetainingCapacity(@min(n, entries.items.len));
            return entries.toOwnedSlice(gpa);
        }

        fn entryLessThan(_: void, a: Entry, b: Entry) bool {
            if (a.count != b.count) return a.count > b.count;
            // `is_string` is comptime-known, so only one branch is compiled:
            // `<` on two slices would not compile.
            return if (is_string) std.mem.lessThan(u8, a.key, b.key) else a.key < b.key;
        }
    };
}

/// What --stats reports.
pub const Stats = struct {
    files_searched: usize = 0,
    files_matched: usize = 0,
    lines_matched: usize = 0,
    matches_per_file: Counter([]const u8) = .{},

    pub fn deinit(self: *Stats, gpa: Allocator) void {
        self.matches_per_file.deinit(gpa);
        self.* = undefined;
    }

    /// Records that `path` was searched and had `matches` selected lines.
    /// `path` must outlive the Stats.
    pub fn record(self: *Stats, gpa: Allocator, path: []const u8, matches: usize) Allocator.Error!void {
        self.files_searched += 1;
        if (matches == 0) return;
        self.files_matched += 1;
        self.lines_matched += matches;
        try self.matches_per_file.add(gpa, path, matches);
    }

    pub fn write(self: Stats, gpa: Allocator, w: *Io.Writer, elapsed: Io.Duration) (Allocator.Error || Io.Writer.Error)!void {
        try w.print(
            \\--- stats ---
            \\files searched: {d}
            \\files matched:  {d}
            \\matching lines: {d}
            \\elapsed:        {f}
            \\
        , .{ self.files_searched, self.files_matched, self.lines_matched, elapsed });

        const top = try self.matches_per_file.topN(gpa, 5);
        defer gpa.free(top);
        if (top.len == 0) return;
        try w.writeAll("top files:\n");
        for (top) |entry| try w.print("{d:>6}  {s}\n", .{ entry.count, entry.key });
    }
};

test "Counter counts integers" {
    const gpa = std.testing.allocator;
    var counter: Counter(u8) = .{};
    defer counter.deinit(gpa);

    for ("hello world") |byte| try counter.add(gpa, byte, 1);
    try std.testing.expectEqual(3, counter.get('l'));
    try std.testing.expectEqual(0, counter.get('z'));

    const top = try counter.topN(gpa, 2);
    defer gpa.free(top);
    try std.testing.expectEqual(2, top.len);
    try std.testing.expectEqual('l', top[0].key); // 3 times
    try std.testing.expectEqual('o', top[1].key); // 2 times
}

test "Counter counts strings and breaks ties by key" {
    const gpa = std.testing.allocator;
    var counter: Counter([]const u8) = .{};
    defer counter.deinit(gpa);

    try counter.add(gpa, "b.txt", 2);
    try counter.add(gpa, "a.txt", 2);
    try counter.add(gpa, "c.txt", 5);

    const top = try counter.topN(gpa, 10);
    defer gpa.free(top);
    try std.testing.expectEqual(3, top.len);
    try std.testing.expectEqualStrings("c.txt", top[0].key);
    try std.testing.expectEqualStrings("a.txt", top[1].key);
    try std.testing.expectEqualStrings("b.txt", top[2].key);
}

test "Stats.write prints a summary and the top files" {
    const gpa = std.testing.allocator;
    var stats: Stats = .{};
    defer stats.deinit(gpa);
    try stats.record(gpa, "a.txt", 2);
    try stats.record(gpa, "b.txt", 0);
    try stats.record(gpa, "c.txt", 5);

    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    // A fixed duration keeps the output predictable.
    try stats.write(gpa, &out.writer, .fromMilliseconds(12));
    try std.testing.expectEqualStrings(
        \\--- stats ---
        \\files searched: 3
        \\files matched:  2
        \\matching lines: 7
        \\elapsed:        12ms
        \\top files:
        \\     5  c.txt
        \\     2  a.txt
        \\
    , out.written());
}
