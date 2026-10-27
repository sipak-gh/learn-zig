const std = @import("std");

const Shape = union(enum) {
    circle: struct { r: f64 },
    square: struct { side: f64 },
    rect: struct { w: f64, h: f64 },
};

fn name(shape: Shape) []const u8 {
    // `inline else` makes one prong per remaining tag. In each copy, `tag`
    // and the payload's type are comptime-known.
    return switch (shape) {
        inline else => |payload, tag| std.fmt.comptimePrint("{s} with {d} field(s)", .{
            @tagName(tag),
            @typeInfo(@TypeOf(payload)).@"struct".field_names.len,
        }),
    };
}

pub fn main() void {
    // The elements of a tuple have different types. A normal `for` can't
    // loop over them; `inline for` unrolls into one copy per element.
    const values = .{ @as(u8, 42), @as(i16, -7), true, 2.5 };
    inline for (values) |v| {
        std.debug.print("{s}: {any}\n", .{ @typeName(@TypeOf(v)), v });
    }

    // `inline while` unrolls too; the counter must be comptime.
    comptime var bits = 8;
    inline while (bits <= 64) : (bits *= 2) {
        std.debug.print("u{d} max = {d}\n", .{ bits, std.math.maxInt(@Int(.unsigned, bits)) });
    }

    std.debug.print("{s}\n", .{name(.{ .rect = .{ .w = 1, .h = 2 } })});
    std.debug.print("{s}\n", .{name(.{ .circle = .{ .r = 1 } })});
}
