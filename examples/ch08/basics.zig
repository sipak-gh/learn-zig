const std = @import("std");

const Point = struct { x: i32, y: i32 };

pub fn main(init: std.process.Init) !void {
    // A general-purpose allocator, set up for us by the start code.
    const gpa = init.gpa;

    // alloc/free: a slice of N items. The contents start undefined.
    const squares = try gpa.alloc(u64, 5);
    defer gpa.free(squares);
    for (squares, 0..) |*sq, i| sq.* = i * i;
    std.debug.print("squares: {any}\n", .{squares});

    // create/destroy: exactly one item, returned as a pointer.
    const p = try gpa.create(Point);
    defer gpa.destroy(p);
    p.* = .{ .x = 3, .y = 4 };
    std.debug.print("point: ({d}, {d})\n", .{ p.x, p.y });

    // dupe: copy a slice into new memory that we own.
    const name = try gpa.dupe(u8, "seek");
    defer gpa.free(name);
    name[0] = 'S';
    std.debug.print("name: {s}\n", .{name});

    // print: format into newly allocated memory.
    const msg = try gpa.print("{s} has {d} letters", .{ name, name.len });
    defer gpa.free(msg);
    std.debug.print("msg: {s}\n", .{msg});

    // realloc: change the size, keeping the contents. The result may live
    // at a new address, so always use the returned slice.
    var buf = try gpa.alloc(u8, 3);
    @memcpy(buf, "abc");
    buf = try gpa.realloc(buf, 6);
    defer gpa.free(buf);
    @memcpy(buf[3..], "def");
    std.debug.print("buf: {s}\n", .{buf});
}
