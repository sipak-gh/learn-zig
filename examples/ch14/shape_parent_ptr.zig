const std = @import("std");

/// Pattern 3: the interface is a field inside the implementation, like
/// std.Io.Writer. It can hold data shared by all shapes (here `name`), and
/// callers pass `*Shape` around.
const Shape = struct {
    vtable: *const VTable,
    name: []const u8,

    const VTable = struct {
        area: *const fn (shape: *const Shape) f64,
    };

    fn area(shape: *const Shape) f64 {
        return shape.vtable.area(shape);
    }
};

const Circle = struct {
    radius: f64,
    shape: Shape = .{ .vtable = &.{ .area = area }, .name = "circle" },

    fn area(shape: *const Shape) f64 {
        // `shape` points at the `shape` field of some Circle. Step back
        // from the field to the struct that contains it.
        const c: *const Circle = @alignCast(@fieldParentPtr("shape", shape));
        return std.math.pi * c.radius * c.radius;
    }
};

const Rect = struct {
    width: f64,
    height: f64,
    shape: Shape = .{ .vtable = &.{ .area = area }, .name = "rect" },

    fn area(shape: *const Shape) f64 {
        const r: *const Rect = @alignCast(@fieldParentPtr("shape", shape));
        return r.width * r.height;
    }
};

fn describe(shape: *const Shape) void {
    std.debug.print("{s}: {d:.2}\n", .{ shape.name, shape.area() });
}

pub fn main() void {
    const circle: Circle = .{ .radius = 1 };
    const rect: Rect = .{ .width = 2, .height = 3 };

    // Always take the address of the field inside the object.
    describe(&circle.shape);
    describe(&rect.shape);

    std.debug.print("@offsetOf(Rect, \"shape\") = {d}\n", .{@offsetOf(Rect, "shape")});
}
