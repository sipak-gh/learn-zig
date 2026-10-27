const std = @import("std");
const Allocator = std.mem.Allocator;

/// A cut-down std.ArrayList: the same fields and the same growth idea.
fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The elements in use. `items.len` is the length of the list.
        items: []T,
        /// How many elements fit before we must allocate again.
        capacity: usize,

        pub const empty: Self = .{ .items = &.{}, .capacity = 0 };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            gpa.free(self.allocatedSlice());
            self.* = undefined;
        }

        /// All the memory we own, used or not.
        fn allocatedSlice(self: Self) []T {
            return self.items.ptr[0..self.capacity];
        }

        pub fn append(self: *Self, gpa: Allocator, value: T) Allocator.Error!void {
            if (self.items.len == self.capacity) try self.grow(gpa);
            self.items.len += 1;
            self.items[self.items.len - 1] = value;
        }

        fn grow(self: *Self, gpa: Allocator) Allocator.Error!void {
            // Start with at least one cache line of elements; this is
            // computed at compile time from the size of T.
            const min_capacity = comptime @max(1, 64 / @sizeOf(T));
            const new_capacity = @max(min_capacity, self.capacity * 2);
            const new_memory = try gpa.alloc(T, new_capacity);
            @memcpy(new_memory[0..self.items.len], self.items);
            gpa.free(self.allocatedSlice());
            self.items = new_memory[0..self.items.len];
            self.capacity = new_capacity;
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var bytes: List(u8) = .empty;
    defer bytes.deinit(gpa);
    var points: List([3]f64) = .empty;
    defer points.deinit(gpa);

    for (0..100) |i| {
        try bytes.append(gpa, @intCast(i));
        try points.append(gpa, .{ 0, 0, @floatFromInt(i) });
    }
    std.debug.print("bytes:  len {d}, capacity {d}\n", .{ bytes.items.len, bytes.capacity });
    std.debug.print("points: len {d}, capacity {d}\n", .{ points.items.len, points.capacity });
    std.debug.print("last point: {any}\n", .{points.items[99]});
}
