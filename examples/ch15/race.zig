const std = @import("std");

var counter: usize = 0;

fn bump() void {
    for (0..1_000_000) |_| counter += 1;
}

pub fn main(init: std.process.Init) !void {
    var group: std.Io.Group = .init;
    try group.concurrent(init.io, bump, .{});
    try group.concurrent(init.io, bump, .{});
    try group.await(init.io);
    std.debug.print("counter = {d}\n", .{counter});
}
