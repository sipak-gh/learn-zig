const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // An empty list owns no memory yet. Every call that may grow it takes
    // the allocator.
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);

    try list.append(gpa, 10);
    try list.append(gpa, 20);
    try list.appendSlice(gpa, &.{ 30, 40, 50 });
    show("appended", list);

    // `items` is a plain slice of the elements: index it, loop over it.
    list.items[0] = 11;
    var sum: i32 = 0;
    for (list.items) |x| sum += x;
    std.debug.print("sum {d}, capacity {d}\n", .{ sum, list.capacity });

    try list.insert(gpa, 1, 15); // shifts the rest right
    show("insert(1, 15)", list);
    _ = list.orderedRemove(0); // shifts the rest left: O(n)
    show("orderedRemove(0)", list);
    _ = list.swapRemove(0); // moves the last item into the hole: O(1)
    show("swapRemove(0)", list);

    std.debug.print("pop: {?d}\n", .{list.pop()});
    std.debug.print("last: {?d}\n", .{list.last()});
    show("now", list);

    list.clearRetainingCapacity();
    std.debug.print("cleared: len {d}, capacity {d}\n", .{ list.items.len, list.capacity });
}

fn show(label: []const u8, list: std.ArrayList(i32)) void {
    std.debug.print("{s:<17} {any}\n", .{ label, list.items });
}
