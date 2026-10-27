const std = @import("std");
const Io = std.Io;

// Fix 1: make the counter atomic.
var atomic_counter: std.atomic.Value(usize) = .init(0);

fn bumpAtomic() void {
    for (0..1_000_000) |_| _ = atomic_counter.fetchAdd(1, .monotonic);
}

// Fix 2: keep a plain counter, but only touch it while holding a lock.
var mutex: Io.Mutex = .init;
var locked_counter: usize = 0;

fn bumpLocked(io: Io) void {
    for (0..1_000_000) |_| {
        mutex.lockUncancelable(io);
        defer mutex.unlock(io);
        locked_counter += 1;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var group: Io.Group = .init;
    try group.concurrent(io, bumpAtomic, .{});
    try group.concurrent(io, bumpAtomic, .{});
    try group.concurrent(io, bumpLocked, .{io});
    try group.concurrent(io, bumpLocked, .{io});
    try group.await(io);
    std.debug.print("atomic = {d}, mutex = {d}\n", .{ atomic_counter.load(.monotonic), locked_counter });
}
