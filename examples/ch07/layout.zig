const std = @import("std");

/// A packed struct lays its fields out bit by bit, here in exactly 8 bits.
const Permissions = packed struct(u8) {
    read: bool = false,
    write: bool = false,
    exec: bool = false,
    _unused: u5 = 0,
};

/// A normal struct: Zig may reorder fields to save space.
const Normal = struct { a: u8, b: u32, c: u8 };

/// An extern struct: C's layout rules, fields in the order written.
const CCompatible = extern struct { a: u8, b: u32, c: u8 };

/// An opaque type has unknown size and layout. You only ever hold
/// pointers to it, usually handles from a C library.
const Handle = opaque {};

pub fn main() void {
    const p: Permissions = .{ .read = true, .exec = true };
    std.debug.print("bits: {b:0>8}, size {d}\n", .{ @backingInt(p), @sizeOf(Permissions) });

    const q: Permissions = @fromBackingInt(0b010);
    std.debug.print("write only: {}\n", .{q.write and !q.read});

    std.debug.print("@sizeOf(Normal) = {d}, @sizeOf(CCompatible) = {d}\n", .{ @sizeOf(Normal), @sizeOf(CCompatible) });
    std.debug.print("@sizeOf(*Handle) = {d}\n", .{@sizeOf(*Handle)});
}
