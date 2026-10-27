const std = @import("std");
const Io = std.Io;

/// Sums one chunk. Each task writes to its own `out`, so no two tasks
/// ever touch the same memory.
fn sumChunk(chunk: []const u64, out: *u64) void {
    var total: u64 = 0;
    for (chunk) |n| total += n;
    out.* = total;
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa;

    const numbers = try gpa.alloc(u64, 1_000_000);
    defer gpa.free(numbers);
    for (numbers, 1..) |*n, i| n.* = i;

    const task_count = 4;
    var partial: [task_count]u64 = undefined;
    const chunk_len = numbers.len / task_count;

    var group: Io.Group = .init;
    // If anything below fails, stop the tasks before `partial` and
    // `numbers` go away. After a successful `await` this does nothing.
    defer group.cancel(io);

    for (0..task_count) |t| {
        const start = t * chunk_len;
        const end = if (t == task_count - 1) numbers.len else start + chunk_len;
        group.async(io, sumChunk, .{ numbers[start..end], &partial[t] });
    }
    // Wait for every task in the group.
    try group.await(io);

    var total: u64 = 0;
    for (partial, 0..) |p, t| {
        std.debug.print("chunk {d}: {d}\n", .{ t, p });
        total += p;
    }
    std.debug.print("total:   {d}\n", .{total});
}
