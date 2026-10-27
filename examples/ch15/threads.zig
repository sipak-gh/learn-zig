const std = @import("std");

var hits: std.atomic.Value(usize) = .init(0);

fn work(id: usize, rounds: usize) void {
    for (0..rounds) |_| _ = hits.fetchAdd(1, .monotonic);
    std.debug.print("thread {d} done\n", .{id});
}

pub fn main() !void {
    const cpus = std.Thread.getCpuCount() catch 1;
    std.debug.print("{d} CPUs\n", .{cpus});

    var threads: [3]std.Thread = undefined;
    for (&threads, 0..) |*t, id| {
        // A real OS thread. `args` is a tuple matching `work`'s parameters.
        t.* = try std.Thread.spawn(.{}, work, .{ id, 1000 });
    }
    // Every spawned thread must be joined (or detached).
    for (threads) |t| t.join();

    std.debug.print("hits = {d}\n", .{hits.load(.monotonic)});
}
