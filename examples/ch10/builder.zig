const std = @import("std");

/// Returns "1, 2, 3, ..., n". The caller owns the result.
fn numberList(gpa: std.mem.Allocator, n: usize) ![]u8 {
    // An ArrayList(u8) is a growable string.
    var out: std.ArrayList(u8) = .empty;
    // If anything fails, free what we built so far.
    errdefer out.deinit(gpa);

    for (1..n + 1) |i| {
        if (i > 1) try out.appendSlice(gpa, ", ");
        try out.print(gpa, "{d}", .{i});
    }
    // Hand the memory to the caller. The list is empty afterwards.
    return out.toOwnedSlice(gpa);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const text = try numberList(gpa, 12);
    defer gpa.free(text);
    std.debug.print("{s}\n", .{text});

    // If you know the size up front, allocate once.
    var squares: std.ArrayList(u64) = try .initCapacity(gpa, 5);
    defer squares.deinit(gpa);
    for (1..6) |i| squares.appendAssumeCapacity(i * i); // can't fail
    std.debug.print("{any} (capacity {d})\n", .{ squares.items, squares.capacity });
}
