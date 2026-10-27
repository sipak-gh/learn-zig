const std = @import("std");

const Job = struct { name: []const u8, priority: u8 };

/// Lower priority number = more urgent. Returning .lt means "a comes out first".
fn moreUrgent(_: void, a: Job, b: Job) std.math.Order {
    return std.math.order(a.priority, b.priority);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // PriorityQueue: pop always returns the most urgent item.
    var jobs: std.PriorityQueue(Job, void, moreUrgent) = .empty;
    defer jobs.deinit(gpa);
    try jobs.push(gpa, .{ .name = "backup", .priority = 3 });
    try jobs.push(gpa, .{ .name = "fire alarm", .priority = 0 });
    try jobs.push(gpa, .{ .name = "email", .priority = 2 });
    try jobs.push(gpa, .{ .name = "coffee", .priority = 1 });
    std.debug.print("next up: {s}\n", .{jobs.peek().?.name});
    while (jobs.pop()) |job| std.debug.print("  {d} {s}\n", .{ job.priority, job.name });

    // Deque: push and pop at both ends in O(1).
    var line: std.Deque(u32) = .empty;
    defer line.deinit(gpa);
    try line.pushBack(gpa, 1);
    try line.pushBack(gpa, 2);
    try line.pushFront(gpa, 0);
    try line.pushBack(gpa, 3);
    std.debug.print("front {?d}, back {?d}, len {d}\n", .{ line.front(), line.back(), line.len });
    std.debug.print("popFront {?d}, popBack {?d}\n", .{ line.popFront(), line.popBack() });
    var it = line.iterator();
    std.debug.print("left:", .{});
    while (it.next()) |x| std.debug.print(" {d}", .{x});
    std.debug.print("\n", .{});
}
