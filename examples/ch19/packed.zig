const std = @import("std");

/// File permission bits, as in `chmod`: one bool per bit, lowest first.
const Mode = packed struct(u9) {
    other_x: bool = false,
    other_w: bool = false,
    other_r: bool = false,
    group_x: bool = false,
    group_w: bool = false,
    group_r: bool = false,
    owner_x: bool = false,
    owner_w: bool = false,
    owner_r: bool = false,
};

/// The same three fields with the three layouts.
const Auto = struct { a: bool, b: u32, c: bool }; // the compiler may reorder
const C = extern struct { a: bool, b: u32, c: bool }; // C's rules, in order
const Bits = packed struct { a: bool, b: u30, c: bool }; // bits of one integer

pub fn main() void {
    const mode: Mode = .{ .owner_r = true, .owner_w = true, .group_r = true, .other_r = true };
    std.debug.print("mode as octal: {o}\n", .{@as(u9, @bitCast(mode))});

    const exec: Mode = @bitCast(@as(u9, 0o755));
    std.debug.print("0o755 owner_x={} group_w={}\n", .{ exec.owner_x, exec.group_w });

    std.debug.print("auto: {d} bytes, extern: {d} bytes, packed: {d} bytes\n", .{
        @sizeOf(Auto), @sizeOf(C), @sizeOf(Bits),
    });
    std.debug.print("offset of b: extern byte {d}, packed bit {d}\n", .{
        @offsetOf(C, "b"), @bitOffsetOf(Bits, "b"),
    });

    // Alignment: the address of a value is a multiple of its alignment.
    std.debug.print("align of u8, u32, u64: {d} {d} {d}\n", .{ @alignOf(u8), @alignOf(u32), @alignOf(u64) });
    var buffer: [64]u8 align(16) = undefined;
    std.debug.print("buffer address % 16 = {d}\n", .{@intFromPtr(&buffer) % 16});
}
