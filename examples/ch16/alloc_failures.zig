const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// Two owned copies of strings.
const Pair = struct {
    first: []u8,
    second: []u8,

    fn init(gpa: Allocator, first: []const u8, second: []const u8) Allocator.Error!Pair {
        const a = try gpa.dupe(u8, first);
        // If the second copy fails, nobody else can free the first one.
        errdefer gpa.free(a);
        const b = try gpa.dupe(u8, second);
        return .{ .first = a, .second = b };
    }

    fn deinit(pair: Pair, gpa: Allocator) void {
        gpa.free(pair.first);
        gpa.free(pair.second);
    }
};

/// The code under test. Its first parameter must be the allocator.
fn makePair(gpa: Allocator, first: []const u8, second: []const u8) !void {
    const pair: Pair = try .init(gpa, first, second);
    defer pair.deinit(gpa);
    try testing.expectEqualStrings(first, pair.first);
}

test "Pair.init cleans up when an allocation fails" {
    // Runs makePair once normally, counting allocations, then once more
    // for each allocation with that allocation failing.
    try testing.checkAllAllocationFailures(testing.allocator, makePair, .{ "fox", "dog" });
}
