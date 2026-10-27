const std = @import("std");

/// A tagged union: a value is exactly one of these, and Zig remembers which.
const Shape = union(enum) {
    circle: f64, // radius
    rect: struct { w: f64, h: f64 },
    point, // no payload (void)

    pub fn area(shape: Shape) f64 {
        // `switch` must handle every tag. `|r|` captures the payload.
        return switch (shape) {
            .circle => |r| std.math.pi * r * r,
            .rect => |r| r.w * r.h,
            .point => 0,
        };
    }

    /// `|*r|` captures a pointer to the payload, so we can change it.
    pub fn scale(shape: *Shape, factor: f64) void {
        switch (shape.*) {
            .circle => |*r| r.* *= factor,
            .rect => |*r| {
                r.w *= factor;
                r.h *= factor;
            },
            .point => {},
        }
    }
};

pub fn main() void {
    var shapes = [_]Shape{
        .{ .circle = 1 },
        .{ .rect = .{ .w = 2, .h = 3 } },
        .point,
    };

    for (&shapes) |*shape| {
        shape.scale(2);
        std.debug.print("{t}: area {d:.2}\n", .{ shape.*, shape.area() });
    }

    // A tagged union compares against its tags.
    const first = shapes[0];
    std.debug.print("first is a circle: {}\n", .{first == .circle});

    // `if` with a tag check, then read the payload directly.
    if (first == .circle) std.debug.print("radius {d}\n", .{first.circle});

    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
