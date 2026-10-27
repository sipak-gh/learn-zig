const std = @import("std");

const Money = struct {
    cents: i64,

    /// Called for the `{f}` specifier.
    pub fn format(m: Money, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const sign = if (m.cents < 0) "-" else "";
        const abs = @abs(m.cents);
        try w.print("{s}${d}.{d:0>2}", .{ sign, abs / 100, abs % 100 });
    }
};

const Line = struct {
    item: []const u8,
    price: Money,

    // A format method can use {f} on its fields.
    pub fn format(line: Line, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.print("{s}: {f}", .{ line.item, line.price });
    }
};

pub fn main(init: std.process.Init) !void {
    const price: Money = .{ .cents = 1999 };
    std.debug.print("price: {f}\n", .{price});
    std.debug.print("refund: {f}\n", .{Money{ .cents = -5 }});

    // {any} ignores the format method and prints the fields.
    std.debug.print("any: {any}\n", .{price});

    // Works with every writer: stdout, buffers, allocated strings.
    const line: Line = .{ .item = "book", .price = price };
    const text = try init.gpa.print("[{f}]", .{line});
    defer init.gpa.free(text);
    std.debug.print("{s}\n", .{text});
}
