const std = @import("std");

pub fn main() void {
    // A list of types. Types only exist at compile time, so the loop over
    // them must be unrolled by the compiler: `inline for`.
    inline for (.{ u8, i16, u32, f64 }) |T| {
        std.debug.print("{s}: {d} bits\n", .{ @typeName(T), @bitSizeOf(T) });
    }
}
