const std = @import("std");

const Circle = struct {
    radius: f64,
    pub fn area(c: Circle) f64 {
        return std.math.pi * c.radius * c.radius;
    }
};

const Rect = struct {
    width: f64,
    height: f64,
    pub fn area(r: Rect) f64 {
        return r.width * r.height;
    }
};

/// Pattern 1: a tagged union. The set of shapes is closed: it is exactly
/// the fields listed here.
const Shape = union(enum) {
    circle: Circle,
    rect: Rect,
    /// A variant can be plain data, without its own type and methods.
    square: f64,

    fn area(shape: Shape) f64 {
        return switch (shape) {
            .circle => |c| c.area(),
            .rect => |r| r.area(),
            .square => |side| side * side,
        };
    }

    fn name(shape: Shape) []const u8 {
        return @tagName(shape);
    }
};

/// When every variant has the same method, `inline else` writes the
/// switch for you.
const Shape2 = union(enum) {
    circle: Circle,
    rect: Rect,

    fn area(shape: Shape2) f64 {
        return switch (shape) {
            inline else => |s| s.area(),
        };
    }
};

pub fn main() void {
    const shapes = [_]Shape{
        .{ .circle = .{ .radius = 1 } },
        .{ .rect = .{ .width = 2, .height = 3 } },
        .{ .square = 4 },
    };
    for (shapes) |shape| std.debug.print("{s}: {d:.2}\n", .{ shape.name(), shape.area() });

    const s2: Shape2 = .{ .rect = .{ .width = 5, .height = 5 } };
    std.debug.print("Shape2 rect: {d:.2}\n", .{s2.area()});
    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
