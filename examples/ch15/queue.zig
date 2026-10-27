const std = @import("std");
const Io = std.Io;

fn producer(io: Io, queue: *Io.Queue(u32)) Io.Cancelable!void {
    // Closing tells the consumer that nothing more is coming.
    defer queue.close(io);
    for (1..6) |i| {
        // Blocks while the queue is full.
        queue.putOne(io, @intCast(i * i)) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
        std.debug.print("put {d}\n", .{i * i});
    }
}

fn consumer(io: Io, queue: *Io.Queue(u32), sum: *u32) Io.Cancelable!void {
    while (true) {
        // Blocks while the queue is empty. Once it is closed *and* empty,
        // getOne returns error.Closed.
        const n = queue.getOne(io) catch |err| switch (err) {
            error.Closed => return,
            error.Canceled => |e| return e,
        };
        std.debug.print("        got {d}\n", .{n});
        sum.* += n;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // The queue doesn't allocate: it uses the buffer you give it, so it
    // holds at most 2 items at a time.
    var buffer: [2]u32 = undefined;
    var queue: Io.Queue(u32) = .init(&buffer);
    var sum: u32 = 0;

    // Each side waits for the other, so they must really run at the same
    // time: `concurrent`, not `async`.
    var group: Io.Group = .init;
    defer group.cancel(io);
    try group.concurrent(io, producer, .{ io, &queue });
    try group.concurrent(io, consumer, .{ io, &queue, &sum });
    try group.await(io);

    std.debug.print("sum = {d}\n", .{sum});
}
