const std = @import("std");
const Allocator = std.mem.Allocator;

/// A generic type is a function that takes types and returns a type.
fn Stack(comptime T: type) type {
    return struct {
        // The struct has no name of its own; @This() refers to it.
        const Self = @This();

        items: std.ArrayList(T) = .empty,

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.items.deinit(gpa);
        }

        pub fn push(self: *Self, gpa: Allocator, value: T) Allocator.Error!void {
            try self.items.append(gpa, value);
        }

        pub fn pop(self: *Self) ?T {
            return self.items.pop();
        }

        pub fn peek(self: Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[self.items.items.len - 1];
        }
    };
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    var numbers: Stack(u32) = .{};
    defer numbers.deinit(gpa);
    for ([_]u32{ 1, 2, 3 }) |n| try numbers.push(gpa, n);
    std.debug.print("peek: {?d}\n", .{numbers.peek()});
    while (numbers.pop()) |n| std.debug.print("pop: {d}\n", .{n});
    std.debug.print("empty: {?d}\n", .{numbers.pop()});

    var words: Stack([]const u8) = .{};
    defer words.deinit(gpa);
    try words.push(gpa, "hello");
    std.debug.print("word: {?s}\n", .{words.peek()});

    // The same arguments give the same type: Stack(u32) is computed once.
    std.debug.print("Stack(u32) == Stack(u32): {}\n", .{Stack(u32) == Stack(u32)});
    std.debug.print("Stack(u32) == Stack(i32): {}\n", .{Stack(u32) == Stack(i32)});
    std.debug.print("name: {s}\n", .{@typeName(Stack(u32))});
}
