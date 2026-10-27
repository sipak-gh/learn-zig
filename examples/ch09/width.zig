const std = @import("std");

pub fn main() void {
    // {[specifier]:[fill][alignment][width].[precision]}
    std.debug.print("[{d:5}]\n", .{42}); // width 5: right-aligned by default
    std.debug.print("[{d:<5}]\n", .{42}); // < left
    std.debug.print("[{d:^5}]\n", .{42}); // ^ center
    std.debug.print("[{d:0>5}]\n", .{42}); // fill with 0, align right
    std.debug.print("[{s:5}]\n", .{"ab"}); // strings too
    std.debug.print("[{s:.>5}]\n", .{"ab"}); // fill with '.', align right
    std.debug.print("[{s:-^9}]\n", .{"mid"});
    std.debug.print("[{d:.2}]\n", .{3.14159}); // precision: 2 decimals
    std.debug.print("[{d:8.3}]\n", .{3.14159}); // width 8, 3 decimals
    std.debug.print("[{x:0>8}]\n", .{0xbeef});

    // A small table.
    const rows = [_]struct { []const u8, u32, f64 }{
        .{ "apples", 3, 1.5 },
        .{ "kiwis", 12, 0.25 },
        .{ "watermelons", 1, 4.0 },
    };
    for (rows) |row| {
        const name, const qty, const price = row;
        std.debug.print("{s:<12}{d:>4} x {d:>5.2}\n", .{ name, qty, price });
    }
}
