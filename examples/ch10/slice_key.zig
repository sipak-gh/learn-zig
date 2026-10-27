const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var map: std.AutoHashMapUnmanaged([]const u8, u32) = .empty;
    defer map.deinit(init.gpa);
    try map.put(init.gpa, "one", 1);
}
