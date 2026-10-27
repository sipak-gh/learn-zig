const std = @import("std");
const Io = std.Io;

var running: std.atomic.Value(usize) = .init(0);
var most_running: std.atomic.Value(usize) = .init(0);

fn job(io: Io, id: usize, slots: *Io.Semaphore) Io.Cancelable!void {
    // Take a permit; blocks while there are none left.
    try slots.wait(io);
    // Give it back when done, so the next job can start.
    defer slots.post(io);

    const now = running.fetchAdd(1, .monotonic) + 1;
    _ = most_running.fetchMax(now, .monotonic);
    std.debug.print("job {d} starts ({d} running)\n", .{ id, now });
    try io.sleep(.fromMilliseconds(50), .awake);
    _ = running.fetchSub(1, .monotonic);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Two permits: at most two jobs hold one at any moment.
    var slots: Io.Semaphore = .{ .permits = 2 };

    var group: Io.Group = .init;
    defer group.cancel(io);
    for (1..7) |id| try group.concurrent(io, job, .{ io, id, &slots });
    try group.await(io);

    std.debug.print("at most {d} jobs ran at once\n", .{most_running.load(.monotonic)});
}
