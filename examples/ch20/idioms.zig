//! The idioms that recur in seek, in one small type.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// A list of song titles. It owns a copy of every title.
const Playlist = struct {
    titles: std.ArrayList([]const u8),
    total_seconds: u32 = 0,

    /// A declaration of type Playlist, so `.empty` works as a decl literal.
    pub const empty: Playlist = .{ .titles = .empty };

    /// A function returning Playlist, so `.initCapacity(…)` works too.
    pub fn initCapacity(gpa: Allocator, n: usize) Allocator.Error!Playlist {
        // Result location: the struct is built directly in the caller's
        // variable, and `.initCapacity` is inferred from the field's type.
        return .{ .titles = try .initCapacity(gpa, n) };
    }

    /// The allocator is a parameter, not a hidden global, and every
    /// method that allocates says so in its signature.
    pub fn deinit(playlist: *Playlist, gpa: Allocator) void {
        for (playlist.titles.items) |title| gpa.free(title);
        playlist.titles.deinit(gpa);
        playlist.* = undefined;
    }

    pub fn add(playlist: *Playlist, gpa: Allocator, title: []const u8, seconds: u32) Allocator.Error!void {
        const owned = try gpa.dupe(u8, title);
        // If append fails, nobody else will free `owned`.
        errdefer gpa.free(owned);
        try playlist.titles.append(gpa, owned);
        playlist.total_seconds += seconds;
    }

    /// A concrete interface type instead of `anytype`: the signature says
    /// exactly what `w` must be, and the function is compiled once.
    pub fn write(playlist: Playlist, w: *Io.Writer) Io.Writer.Error!void {
        for (playlist.titles.items, 1..) |title, n| try w.print("{d}. {s}\n", .{ n, title });
        try w.print("total: {d}:{d:0>2}\n", .{ playlist.total_seconds / 60, playlist.total_seconds % 60 });
    }
};

test "decl literals, init/deinit, explicit allocator" {
    const gpa = std.testing.allocator;
    var playlist: Playlist = try .initCapacity(gpa, 2);
    defer playlist.deinit(gpa);
    try playlist.add(gpa, "Intro", 90);
    try playlist.add(gpa, "Theme", 155);

    var buffer: [64]u8 = undefined;
    var w: Io.Writer = .fixed(&buffer);
    try playlist.write(&w);
    try std.testing.expectEqualStrings("1. Intro\n2. Theme\ntotal: 4:05\n", w.buffered());
}

fn fillPlaylist(gpa: Allocator) !void {
    var playlist: Playlist = .empty;
    defer playlist.deinit(gpa);
    try playlist.add(gpa, "Intro", 90);
    try playlist.add(gpa, "Theme", 155);
    try playlist.add(gpa, "Outro", 60);
}

test "errdefer: no leak, whichever allocation fails" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fillPlaylist, .{});
}
