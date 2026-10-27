const std = @import("std");
const Io = std.Io;

/// Ticks forever. Every `io.sleep` is a cancelation point: once someone
/// asks this task to stop, the next sleep returns error.Canceled.
fn ticker(io: Io) Io.Cancelable!void {
    defer std.debug.print("ticker: cleaning up\n", .{});
    var n: usize = 0;
    while (true) {
        try io.sleep(.fromMilliseconds(40), .awake);
        n += 1;
        std.debug.print("tick {d}\n", .{n});
    }
}

/// Pure computation has no cancelation points of its own, so it checks
/// for a cancelation request now and then.
fn crunch(io: Io) Io.Cancelable!u64 {
    var x: u64 = 0;
    var i: u64 = 0;
    while (true) : (i += 1) {
        x +%= i *% i;
        if (i % 1_000_000 == 0) try io.checkCancel();
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var tick = try io.concurrent(ticker, .{io});
    try io.sleep(.fromMilliseconds(100), .awake);
    // Request cancelation, then wait for the task to finish.
    tick.cancel(io) catch |err| std.debug.print("ticker returned {t}\n", .{err});

    var work = try io.concurrent(crunch, .{io});
    try io.sleep(.fromMilliseconds(20), .awake);
    if (work.cancel(io)) |x| {
        std.debug.print("crunch finished: {d}\n", .{x});
    } else |err| {
        std.debug.print("crunch returned {t}\n", .{err});
    }
}
