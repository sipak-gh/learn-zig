const std = @import("std");

const Color = enum { red, green };
const Point = struct { x: i32, y: i32 };

pub fn main() void {
    const n: u8 = 200;
    std.debug.print("d: {d}  x: {x}  X: {X}  b: {b}  o: {o}\n", .{ n, n, n, n, n });
    std.debug.print("c: {c}  u: {u}\n", .{ 'z', '⚡' });
    std.debug.print("e: {e}  d: {d}\n", .{ 1234.5, 1234.5 });

    std.debug.print("s: {s}  q: {q}\n", .{ "tab\there", "tab\there" });
    std.debug.print("x on a string: {x}\n", .{"Zig"});

    std.debug.print("t: {t} {t}\n", .{ Color.green, error.NotFound });
    std.debug.print("B: {B}  Bi: {Bi:.2}\n", .{ 1_500_000, 1_500_000 });

    const maybe: ?u32 = null;
    const some: ?u32 = 42;
    std.debug.print("?: {?d} {?d}\n", .{ maybe, some });

    const ok: anyerror!u32 = 7;
    const bad: anyerror!u32 = error.Oops;
    std.debug.print("!: {!d} {!d}\n", .{ ok, bad });

    // any: the default format, works for structs, arrays, slices, ...
    const p: Point = .{ .x = 1, .y = -2 };
    std.debug.print("any: {any}\n", .{p});
    std.debug.print("any: {any}\n", .{[_]u8{ 1, 2, 3 }});

    // *: the address, not the value.
    std.debug.print("*: {*}\n", .{&p});

    // Arguments by position or by name; {{ and }} are literal braces.
    std.debug.print("{1s} {0s}!\n", .{ "world", "hello" });
    std.debug.print("{[name]s} is {[age]d}\n", .{ .name = "Ziggy", .age = 9 });
    std.debug.print("{{d}} prints braces\n", .{});
}
