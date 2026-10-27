const std = @import("std");

// `inline fn` pastes the body into every call site. Rarely needed: the
// optimizer already inlines small functions when it helps.
inline fn isEven(n: u32) bool {
    return n % 2 == 0;
}

pub fn main() void {
    for (1..5) |i| {
        const n: u32 = @intCast(i);
        std.debug.print("{d} even? {}\n", .{ n, isEven(n) });
    }
}
