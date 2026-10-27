const std = @import("std");
const path = std.fs.path;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const joined = try path.join(gpa, &.{ "src", "util", "str.zig" });
    defer gpa.free(joined);

    std.debug.print("join:      {s}\n", .{joined});
    std.debug.print("basename:  {s}\n", .{path.basename(joined)});
    std.debug.print("dirname:   {?s}\n", .{path.dirname(joined)});
    std.debug.print("extension: {s}\n", .{path.extension(joined)});
    std.debug.print("stem:      {s}\n", .{path.stem(joined)});
    std.debug.print("dirname of \"str.zig\": {?s}\n", .{path.dirname("str.zig")});
    std.debug.print("absolute?  {} {}\n", .{ path.isAbsolute(joined), path.isAbsolute("/etc") });
}
