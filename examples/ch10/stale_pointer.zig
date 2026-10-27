const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 1);

    // A pointer into `items`...
    const first = &list.items[0];
    std.debug.print("before: {d}, capacity {d}\n", .{ first.*, list.capacity });

    // ...is only valid until the list grows. Lock it to catch mistakes.
    list.lockPointers();
    defer list.unlockPointers();
    for (0..100) |i| try list.append(gpa, @intCast(i));
    std.debug.print("after: {d}\n", .{first.*});
}
