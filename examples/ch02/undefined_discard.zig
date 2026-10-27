const std = @import("std");

pub fn main() void {
    // `undefined`: "no value yet". Reading it before assigning is a bug.
    var total: u32 = undefined;
    total = 10;

    // `_ = expr;` evaluates and throws away a value, on purpose.
    _ = total + 1;

    // @"..." lets any text be an identifier, even keywords.
    const @"error count" = 3;
    const @"fn" = "a keyword as a name";

    std.debug.print("total={d} errors={d} {s}\n", .{ total, @"error count", @"fn" });
}
