const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // An array hash map remembers insertion order.
    var stock: std.array_hash_map.String(u32) = .empty;
    defer stock.deinit(gpa);

    try stock.put(gpa, "pears", 4);
    try stock.put(gpa, "apples", 7);
    try stock.put(gpa, "kiwis", 0);
    try stock.put(gpa, "plums", 12);

    // keys() and values() are plain slices, in insertion order.
    std.debug.print("{d} entries:\n", .{stock.count()});
    for (stock.keys(), stock.values()) |k, v| std.debug.print("  {s} = {d}\n", .{ k, v });

    // orderedRemove keeps the order (O(n)); swapRemove is O(1) but moves
    // the last entry into the gap.
    _ = stock.orderedRemove("apples");
    _ = stock.swapRemove("pears");
    std.debug.print("after removing: ", .{});
    for (stock.keys()) |k| std.debug.print("{s} ", .{k});
    std.debug.print("\n", .{});
}
