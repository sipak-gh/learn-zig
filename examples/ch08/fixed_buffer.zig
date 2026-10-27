const std = @import("std");

pub fn main() void {
    // All memory comes from this stack array; no heap at all.
    var buffer: [64]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buffer);
    const allocator = fba.allocator();

    const a = allocator.dupe(u8, "fits easily") catch unreachable;
    std.debug.print("a = {s}\n", .{a});

    // Ask for more than is left: OutOfMemory is an ordinary error.
    if (allocator.alloc(u8, 100)) |big| {
        std.debug.print("got {d} bytes\n", .{big.len});
    } else |err| {
        std.debug.print("alloc failed: {t}\n", .{err});
    }

    // reset makes the whole buffer available again.
    fba.reset();
    const b = allocator.alloc(u8, 64) catch unreachable;
    std.debug.print("after reset: got {d} bytes\n", .{b.len});
}
