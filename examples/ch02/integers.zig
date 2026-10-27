const std = @import("std");

pub fn main() void {
    const small: u8 = 255; // unsigned, 8 bits: 0..255
    const negative: i32 = -1_000_000; // signed, 32 bits; `_` separates digits
    const big: u64 = 0xFFFF_FFFF; // hexadecimal literal
    const flags: u3 = 0b101; // any width works: u3 holds 0..7
    const tiny: i7 = -64; // i7 holds -64..63
    const size: usize = 1024; // pointer-sized: lengths and indexes
    const letter: u8 = 'A'; // a character literal is just a number

    std.debug.print("{d} {d} {d} {d} {d} {d} {d}\n", .{ small, negative, big, flags, tiny, size, letter });
    std.debug.print("u8: {d}..{d}\n", .{ std.math.minInt(u8), std.math.maxInt(u8) });
    std.debug.print("i7: {d}..{d}\n", .{ std.math.minInt(i7), std.math.maxInt(i7) });
    std.debug.print("u3 takes {d} bits, u64 takes {d} bytes\n", .{ @bitSizeOf(u3), @sizeOf(u64) });

    // Literals without a type are `comptime_int`: exact, unlimited size.
    const huge = 1 << 100;
    std.debug.print("2^100 = {d}, as u8 after >> 96: {d}\n", .{ huge, @as(u8, huge >> 96) });
}
