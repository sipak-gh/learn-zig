const std = @import("std");

pub fn main() !void {
    // Without std.process.Init you set up the allocator yourself.
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    // deinit reports leaks and returns how many there were.
    defer _ = safe.deinit();
    const gpa = safe.allocator();

    const words = try gpa.alloc([]const u8, 2);
    defer gpa.free(words);
    words[0] = "hello";
    words[1] = "allocator";
    std.debug.print("{s} {s}\n", .{ words[0], words[1] });
}
