const std = @import("std");
const Io = std.Io;

fn runner(io: Io, id: usize, start: *Io.Event) Io.Cancelable!void {
    // Blocks until the event is set. If it already is, returns at once.
    try start.wait(io);
    std.debug.print("runner {d} goes\n", .{id});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var start: Io.Event = .unset;
    var group: Io.Group = .init;
    defer group.cancel(io);
    for (1..4) |id| try group.concurrent(io, runner, .{ io, id, &start });

    std.debug.print("ready...\n", .{});
    try io.sleep(.fromMilliseconds(100), .awake);
    std.debug.print("set!\n", .{});
    // Wakes every waiting task, and every future `wait` returns at once.
    start.set(io);

    try group.await(io);
}
