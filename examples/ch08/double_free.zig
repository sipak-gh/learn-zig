const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const data = try gpa.alloc(u8, 16);
    gpa.free(data);
    gpa.free(data); // Bug: freed twice.
}
