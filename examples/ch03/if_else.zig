const std = @import("std");

pub fn main() void {
    var temperature: i32 = 18;
    temperature += 0; // a runtime value

    if (temperature > 25) {
        std.debug.print("hot\n", .{});
    } else if (temperature > 15) {
        std.debug.print("mild\n", .{});
    } else {
        std.debug.print("cold\n", .{});
    }

    // `if` is also an expression that produces a value.
    const coat = if (temperature < 20) "yes" else "no";
    std.debug.print("coat: {s}\n", .{coat});

    // Without braces, the body is a single statement.
    if (temperature == 18) std.debug.print("exactly 18\n", .{});
}
