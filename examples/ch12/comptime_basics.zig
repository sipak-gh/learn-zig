const std = @import("std");

fn fibonacci(n: u32) u64 {
    var a: u64 = 0;
    var b: u64 = 1;
    for (0..n) |_| {
        const next = a + b;
        a = b;
        b = next;
    }
    return a;
}

/// A 256-entry table: true for bytes that may appear in an identifier.
/// The loop runs inside the compiler; the program only contains the result.
const is_ident = blk: {
    var table: [256]bool = @splat(false); // every element false
    for ('a'..'z' + 1) |c| table[c] = true;
    for ('A'..'Z' + 1) |c| table[c] = true;
    for ('0'..'9' + 1) |c| table[c] = true;
    table['_'] = true;
    break :blk table;
};

pub fn main() void {
    // The same function, called at compile time and at run time.
    const at_compile_time = comptime fibonacci(50);
    var n: u32 = 50;
    _ = &n; // pretend n could change, so it is runtime-known
    const at_run_time = fibonacci(n);
    std.debug.print("fib(50) = {d} (comptime) = {d} (runtime)\n", .{ at_compile_time, at_run_time });

    // A comptime variable can change while compiling, never at run time.
    comptime var count = 0;
    inline for (.{ "a", "bb", "ccc" }) |s| count += s.len;
    std.debug.print("total length: {d}\n", .{count});

    const word = "max_len=42";
    var end: usize = 0;
    while (end < word.len and is_ident[word[end]]) end += 1;
    std.debug.print("identifier: {s}\n", .{word[0..end]});
}
