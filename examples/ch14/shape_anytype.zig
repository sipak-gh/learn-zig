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

/// Pattern 4: static duck typing. Any value with an `area` method works,
/// and each call is resolved at compile time.
fn describe(shape: anytype) void {
    std.debug.print("{s}: {d:.2}\n", .{ @typeName(@TypeOf(shape)), shape.area() });
}

/// A tuple can hold different types; `inline for` visits each one with
/// its real type.
fn totalArea(shapes: anytype) f64 {
    var total: f64 = 0;
    inline for (shapes) |s| total += s.area();
    return total;
}

pub fn main() void {
    const circle: Circle = .{ .radius = 1 };
    const rect: Rect = .{ .width = 2, .height = 3 };
    describe(circle);
    describe(rect);
    std.debug.print("total: {d:.2}\n", .{totalArea(.{ circle, rect, rect })});
}
