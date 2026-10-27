const std = @import("std");

// `++` joins arrays whose lengths are known at compile time.
const head = [_]u8{ 1, 2 };
const tail = [_]u8{ 3, 4, 5 };
const joined = head ++ tail; // [5]u8

// String literals are arrays too, so `++` joins them.
const greeting = "hello" ++ ", " ++ "world";

// A 3×3 grid is an array of 3 arrays of 3 bytes.
const Grid = [3][3]u8;

pub fn main() void {
    std.debug.print("joined: {any} ({d} items)\n", .{ joined, joined.len });
    std.debug.print("greeting: {s}\n", .{greeting});

    // Every row, then every cell, starts as '.'.
    var grid: Grid = @splat(@splat('.'));
    grid[1][1] = 'X';
    grid[0][2] = 'O';
    for (grid) |row| std.debug.print("{s}\n", .{&row});

    // Destructuring pulls the elements of an array into separate constants.
    const x, const y, _ = tail;
    std.debug.print("x={d} y={d}\n", .{ x, y });
}
