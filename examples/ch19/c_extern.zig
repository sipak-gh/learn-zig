//! Calling C's standard library directly. Run with `zig run -lc`.

const std = @import("std");

// Declarations of functions that live in libc. The types are C's:
// c_int is C's `int`, and [*:0]const u8 is a NUL-terminated `const char *`.
extern "c" fn abs(x: c_int) c_int;
extern "c" fn strlen(s: [*:0]const u8) usize;
extern "c" fn atoi(s: [*:0]const u8) c_int;
extern "c" fn qsort(
    base: *anyopaque,
    count: usize,
    size: usize,
    compare: *const fn (?*const anyopaque, ?*const anyopaque) callconv(.c) c_int,
) void;

/// C calls this function, so it must use C's calling convention.
fn compareInts(a: ?*const anyopaque, b: ?*const anyopaque) callconv(.c) c_int {
    const x: *const c_int = @ptrCast(@alignCast(a.?));
    const y: *const c_int = @ptrCast(@alignCast(b.?));
    return switch (std.math.order(x.*, y.*)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

pub fn main() void {
    std.debug.print("abs(-7) = {d}\n", .{abs(-7)});
    std.debug.print("strlen(\"hello\") = {d}\n", .{strlen("hello")});
    std.debug.print("atoi(\"42abc\") = {d}\n", .{atoi("42abc")});

    var numbers = [_]c_int{ 42, -3, 17, 0, 8 };
    qsort(&numbers, numbers.len, @sizeOf(c_int), compareInts);
    std.debug.print("qsort: {any}\n", .{numbers});

    // std.c has declarations for much of libc already.
    std.debug.print("getpid() > 0: {}\n", .{std.c.getpid() > 0});
}
