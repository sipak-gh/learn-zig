const std = @import("std");

pub fn main() void {
    const x: u8 = 0b0010_1100;

    std.debug.print("x           = 0b{b:0>8} ({d})\n", .{ x, x });
    std.debug.print("@popCount   = {d}\n", .{@popCount(x)}); // bits set
    std.debug.print("@clz        = {d}\n", .{@clz(x)}); // leading zeros
    std.debug.print("@ctz        = {d}\n", .{@ctz(x)}); // trailing zeros
    std.debug.print("@bitReverse = 0b{b:0>8}\n", .{@bitReverse(x)});
    std.debug.print("@byteSwap   = 0x{x}\n", .{@byteSwap(@as(u32, 0x11223344))});

    // Reinterpret the bits of one type as another of the same size.
    const one: f32 = 1.0;
    std.debug.print("1.0 as bits = 0x{x}\n", .{@as(u32, @bitCast(one))});

    // The shift amount of a u32 must fit in a u5 (0..31):
    // std.math.Log2Int(u32) is u5.
    var amount: std.math.Log2Int(u32) = 0;
    amount += 31;
    std.debug.print("1 << {d}     = 0x{x}\n", .{ amount, @as(u32, 1) << amount });

    // @shlExact asserts that no 1 bits are shifted out.
    std.debug.print("@shlExact   = {d}\n", .{@shlExact(@as(u8, 0b0001_0000), 3)});

    // std.math.shl accepts any amount; bits shifted too far give 0.
    std.debug.print("math.shl    = {d}\n", .{std.math.shl(u8, 1, 9)});

    // Reading a little-endian integer from bytes, as a file format would.
    const bytes = [_]u8{ 0x78, 0x56, 0x34, 0x12 };
    std.debug.print("readInt     = 0x{x}\n", .{std.mem.readInt(u32, &bytes, .little)});
}
