const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    // HTTP status code -> reason phrase.
    var reasons: std.AutoHashMapUnmanaged(u16, []const u8) = .empty;
    defer reasons.deinit(gpa);

    try reasons.put(gpa, 200, "OK");
    try reasons.put(gpa, 404, "Not Found");
    try reasons.put(gpa, 500, "Server Error");
    try reasons.put(gpa, 500, "Internal Server Error"); // replaces the value

    std.debug.print("count: {d}\n", .{reasons.count()});
    std.debug.print("404: {?s}\n", .{reasons.get(404)});
    std.debug.print("418: {?s}\n", .{reasons.get(418)});
    std.debug.print("contains 200: {}\n", .{reasons.contains(200)});

    // getPtr gives a pointer to the value, to change it in place.
    if (reasons.getPtr(200)) |reason| reason.* = "Fine";

    std.debug.print("removed 404: {}\n", .{reasons.remove(404)});

    // Iteration order is unspecified: don't rely on it.
    var it = reasons.iterator();
    while (it.next()) |entry| {
        std.debug.print("{d} => {s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}
