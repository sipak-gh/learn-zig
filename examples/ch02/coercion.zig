const std = @import("std");

pub fn main() void {
    // Widening: every u8 value fits in a u32, so this just works.
    var byte: u8 = 200;
    byte += 0; // (makes `byte` a runtime value; see "comptime-known" below)
    const wide: u32 = byte;
    const signed: i16 = byte; // u8 fits in i16 (but not in i8)

    // Narrowing needs a builtin that says what you mean.
    var big: u32 = 300;
    big += 0;
    const checked: u16 = @intCast(big); // "it fits": checked in safe builds
    const cut: u8 = @truncate(big); // keep the low 8 bits: 300 - 256 = 44

    // Int -> float coerces when the float holds every value exactly.
    const exact: f64 = byte; // f64 holds every u8
    var count: i64 = 7;
    count += 0;
    const f: f64 = @floatFromInt(count); // f64 can't hold every i64: cast
    const back: i32 = @intFromFloat(f * 1.9); // 13.3 -> 13 (toward zero)

    // @as(T, x) is a safe, explicit coercion. Handy where no type is written.
    const sum = @as(u64, byte) + 1000;

    std.debug.print("wide={d} signed={d} checked={d} cut={d}\n", .{ wide, signed, checked, cut });
    std.debug.print("exact={d} f={d} back={d}\n", .{ exact, f, back });
    std.debug.print("sum={d} has type {s}\n", .{ sum, @typeName(@TypeOf(sum)) });
}
