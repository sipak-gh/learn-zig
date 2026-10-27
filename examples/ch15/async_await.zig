const std = @import("std");
const Io = std.Io;

/// Pretends to download a file: waits `ms` milliseconds, then returns its
/// size. `io.sleep` can fail with error.Canceled (more on that later).
fn download(io: Io, name: []const u8, ms: i64) Io.Cancelable!usize {
    try io.sleep(.fromMilliseconds(ms), .awake);
    std.debug.print("  {s} finished\n", .{name});
    return @intCast(ms * 1000);
}

fn both(io: Io) !void {
    const start = Io.Clock.awake.now(io);

    // Start both downloads. Neither call waits for the download to finish.
    var big = io.async(download, .{ io, "big.iso", 200 });
    var small = io.async(download, .{ io, "small.txt", 100 });

    // `await` waits for a result. Every Future must be awaited (or
    // canceled) exactly once, or its resources leak.
    const a = try big.await(io);
    const b = try small.await(io);

    std.debug.print("  {d} + {d} bytes in {f}\n", .{ a, b, start.untilNow(io, .awake) });
}

pub fn main(init: std.process.Init) !void {
    std.debug.print("with init.io:\n", .{});
    try both(init.io);

    // An Io that never starts another thread: `async` just calls the
    // function on the spot.
    var single: Io.Threaded = .init_single_threaded;
    std.debug.print("with a single-threaded Io:\n", .{});
    try both(single.io());

    // `concurrent` refuses instead.
    if (single.io().concurrent(download, .{ single.io(), "x", 1 })) |_| {
        unreachable;
    } else |err| {
        std.debug.print("concurrent: {t}\n", .{err});
    }
}
