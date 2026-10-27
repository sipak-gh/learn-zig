const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // `awake` is monotonic: right for measuring how long something takes.
    const start = Io.Clock.awake.now(io);
    try io.sleep(.fromMilliseconds(20), .awake);
    const elapsed = start.untilNow(io, .awake);
    std.debug.print("slept for about {d} ms\n", .{elapsed.toMilliseconds()});

    // {f} calls Duration.format, which picks a unit.
    const examples = [_]Io.Duration{ .fromNanoseconds(750), .fromMicroseconds(1500), .fromSeconds(90) };
    for (examples) |d| std.debug.print("{f}\n", .{d});
}
