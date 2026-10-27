const std = @import("std");

pub fn main() void {
    std.debug.print("@alignOf(u8)  = {d}\n", .{@alignOf(u8)});
    std.debug.print("@alignOf(u32) = {d}\n", .{@alignOf(u32)});
    std.debug.print("@alignOf(u64) = {d}\n", .{@alignOf(u64)});

    // Four bytes, placed at an address that is valid for a u32.
    const bytes: [4]u8 align(4) = .{ 0x78, 0x56, 0x34, 0x12 };

    // @ptrCast reinterprets the memory behind a pointer. The result depends
    // on the CPU's byte order, so this prints 12345678 on little-endian CPUs.
    const word: *const u32 = @ptrCast(&bytes);
    std.debug.print("word = {x}\n", .{word.*});

    // @bitCast does the same for values, with no pointers involved.
    const same: u32 = @bitCast(bytes);
    std.debug.print("same = {x}\n", .{same});
}
