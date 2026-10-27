const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const kept = try gpa.dupe(u8, "freed properly");
    defer gpa.free(kept);

    // Bug: nobody frees this.
    const lost = try gpa.alloc(u8, 100);
    @memset(lost, 0);

    std.debug.print("done: {s}\n", .{kept});
}
