const std = @import("std");

pub fn main() void {
    // A string literal is a pointer to a null-terminated array of bytes.
    const hello = "héllo";
    std.debug.print("type: {s}\n", .{@typeName(@TypeOf(hello))});
    std.debug.print("len:  {d} bytes\n", .{hello.len});

    // It coerces to a slice, the type almost every function wants.
    const s: []const u8 = hello;
    std.debug.print("s[1] = {d} (0x{x}), s[2] = {d} (0x{x})\n", .{ s[1], s[1], s[2], s[2] });

    // Character literals are integers: their type is comptime_int.
    const c = 'A';
    std.debug.print("'A' = {d}, type {s}\n", .{ c, @typeName(@TypeOf(c)) });
    std.debug.print("'é' = {d} = U+{X:0>4}\n", .{ 'é', 'é' });

    // Escapes work as in C, plus \x and \u{...}.
    const escaped = "tab:\t| newline:\\n | hex:\x41 | unicode:\u{e9}";
    std.debug.print("{s}\n", .{escaped});

    // A multiline string literal: nothing is escaped, no trailing newline.
    const poem =
        \\The quick brown fox
        \\jumps over "the" lazy \dog.
    ;
    std.debug.print("{s}\n", .{poem});
    std.debug.print("poem has {d} bytes\n", .{poem.len});
}
