const std = @import("std");

/// Pattern 2: a fat pointer. A Shape is "a pointer to some object" plus
/// "a pointer to the functions that work on it", like std.mem.Allocator.
const Shape = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        area: *const fn (ptr: *anyopaque) f64,
        name: *const fn (ptr: *anyopaque) []const u8,
    };

    fn area(shape: Shape) f64 {
        return shape.vtable.area(shape.ptr);
    }

    fn name(shape: Shape) []const u8 {
        return shape.vtable.name(shape.ptr);
    }
};

const Circle = struct {
    radius: f64,

    fn area(ptr: *anyopaque) f64 {
        const c: *Circle = @ptrCast(@alignCast(ptr));
        return std.math.pi * c.radius * c.radius;
    }

    fn name(_: *anyopaque) []const u8 {
        return "circle";
    }

    /// One vtable for all circles, stored in the program's constant data.
    const vtable: Shape.VTable = .{ .area = area, .name = name };

    fn shape(c: *Circle) Shape {
        return .{ .ptr = c, .vtable = &vtable };
    }
};

const Rect = struct {
    width: f64,
    height: f64,

    fn area(ptr: *anyopaque) f64 {
        const r: *Rect = @ptrCast(@alignCast(ptr));
        return r.width * r.height;
    }

    fn name(_: *anyopaque) []const u8 {
        return "rect";
    }

    const vtable: Shape.VTable = .{ .area = area, .name = name };

    fn shape(r: *Rect) Shape {
        return .{ .ptr = r, .vtable = &vtable };
    }
};

/// Knows nothing about Circle or Rect. New shapes can be added in other
/// files, even other packages, without changing this function.
fn totalArea(shapes: []const Shape) f64 {
    var total: f64 = 0;
    for (shapes) |s| total += s.area();
    return total;
}

pub fn main() void {
    var circle: Circle = .{ .radius = 1 };
    var rect: Rect = .{ .width = 2, .height = 3 };
    const shapes = [_]Shape{ circle.shape(), rect.shape() };

    for (shapes) |s| std.debug.print("{s}: {d:.2}\n", .{ s.name(), s.area() });
    std.debug.print("total: {d:.2}\n", .{totalArea(&shapes)});

    // The Shape points at `rect`, so it sees changes to it.
    rect.width = 10;
    std.debug.print("rect after resize: {d:.2}\n", .{shapes[1].area()});
    std.debug.print("@sizeOf(Shape) = {d}\n", .{@sizeOf(Shape)});
}
