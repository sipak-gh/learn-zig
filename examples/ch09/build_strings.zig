const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // Joining runtime strings needs new memory, so it needs an allocator.
    const parts = [_][]const u8{ "usr", "local", "bin" };
    const path = try std.mem.join(gpa, "/", &parts);
    defer gpa.free(path);
    std.debug.print("join:    {s}\n", .{path});

    const whole = try std.mem.concat(gpa, u8, &.{ "zig", "-", "0.17" });
    defer gpa.free(whole);
    std.debug.print("concat:  {s}\n", .{whole});

    const fixed = try std.mem.replaceOwned(u8, gpa, "colour and colour", "colour", "color");
    defer gpa.free(fixed);
    std.debug.print("replace: {s}\n", .{fixed});

    // Formatting into new memory: Allocator.print.
    const msg = try gpa.print("{s} has {d} parts", .{ path, parts.len });
    defer gpa.free(msg);
    std.debug.print("print:   {s}\n", .{msg});

    // Formatting into a buffer you already have: std.mem.print. No allocator.
    var buf: [32]u8 = undefined;
    const label = try std.mem.print(&buf, "item-{d:0>3}", .{7});
    std.debug.print("buffer:  {s}\n", .{label});

    // The buffer is too small: error.NoSpaceLeft.
    var tiny: [4]u8 = undefined;
    if (std.mem.print(&tiny, "{d}", .{123456})) |s| {
        std.debug.print("fits: {s}\n", .{s});
    } else |err| {
        std.debug.print("tiny:    {t}\n", .{err});
    }

    // Changing bytes in place needs a mutable copy.
    const upper = try gpa.dupe(u8, "shout");
    defer gpa.free(upper);
    for (upper) |*ch| ch.* = std.ascii.toUpper(ch.*);
    std.debug.print("upper:   {s}\n", .{upper});
}
