const std = @import("std");

pub fn main(init: std.process.Init) !void {
    // A "managed" map stores the allocator, so calls don't take it.
    var ages: std.StringHashMap(u8) = .init(init.gpa);
    defer ages.deinit();

    try ages.put("ada", 36);
    try ages.put("linus", 54);
    std.debug.print("ada: {?d}, count: {d}\n", .{ ages.get("ada"), ages.count() });
}
