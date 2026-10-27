const std = @import("std");

/// A point on a grid. `y` has a default, so you may leave it out.
const Point = struct {
    x: i32,
    y: i32 = 0,

    /// A declaration inside the struct: `Point.origin`.
    pub const origin: Point = .{ .x = 0, .y = 0 };

    /// The usual name for "make a new value".
    pub fn init(x: i32, y: i32) Point {
        return .{ .x = x, .y = y };
    }

    /// Takes the point by value: it only reads.
    pub fn distance(p: Point) u32 {
        return @abs(p.x) + @abs(p.y);
    }

    /// Takes a pointer: it changes the caller's point.
    pub fn move(p: *Point, dx: i32, dy: i32) void {
        p.x += dx;
        p.y += dy;
    }
};

pub fn main() void {
    const a = Point{ .x = 3, .y = 4 }; // typed literal
    const b: Point = .{ .x = 7 }; // the result type gives `.{}` its type; y = 0
    var c: Point = .origin; // decl literal: Point.origin
    const d: Point = .init(5, -2); // decl literal calling Point.init

    std.debug.print("a = {any}\n", .{a});
    std.debug.print("b.y = {d}, d = ({d}, {d})\n", .{ b.y, d.x, d.y });

    // Method call syntax passes the value as the first argument.
    std.debug.print("a.distance() = {d}, Point.distance(a) = {d}\n", .{ a.distance(), Point.distance(a) });

    // `c` is a var, so `c.move` passes `&c` automatically.
    c.move(2, 3);
    c.move(1, 1);
    std.debug.print("c = ({d}, {d})\n", .{ c.x, c.y });

    // Structs are values: assignment copies.
    var e = c;
    e.x = 100;
    std.debug.print("c.x = {d}, e.x = {d}\n", .{ c.x, e.x });

    // Fields work the same through a pointer: no `->` needed.
    const p = &e;
    p.y = -1;
    std.debug.print("e = ({d}, {d}), size {d} bytes\n", .{ e.x, e.y, @sizeOf(Point) });
}
