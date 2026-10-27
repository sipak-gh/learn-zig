const std = @import("std");
const Allocator = std.mem.Allocator;

/// Returns "Hello, NAME!". The caller owns the result and must free it
/// with the same allocator.
fn greet(gpa: Allocator, name: []const u8) Allocator.Error![]u8 {
    return gpa.print("Hello, {s}!", .{name});
}

const Pair = struct {
    first: []u8,
    second: []u8,

    /// Copies both strings. If the second copy fails, the first one is
    /// freed again, so the function never leaks.
    fn init(gpa: Allocator, a: []const u8, b: []const u8) Allocator.Error!Pair {
        const first = try gpa.dupe(u8, a);
        errdefer gpa.free(first); // runs only if we return an error below
        const second = try gpa.dupe(u8, b);
        return .{ .first = first, .second = second };
    }

    fn deinit(self: *Pair, gpa: Allocator) void {
        gpa.free(self.first);
        gpa.free(self.second);
        self.* = undefined;
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const hello = try greet(gpa, "Zig");
    defer gpa.free(hello);
    std.debug.print("{s}\n", .{hello});

    var pair: Pair = try .init(gpa, "left", "right");
    defer pair.deinit(gpa);
    std.debug.print("{s} {s}\n", .{ pair.first, pair.second });

    // A 10-byte buffer: "left" fits, "a much longer string" does not.
    var small: [10]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&small);
    if (Pair.init(fba.allocator(), "left", "a much longer string")) |_| {
        std.debug.print("unexpected success\n", .{});
    } else |err| {
        std.debug.print("Pair.init failed with {t}; end_index after cleanup = {d}\n", .{ err, fba.end_index });
    }
}
