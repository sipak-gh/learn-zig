const std = @import("std");

pub fn main() void {
    const answer = 42; // constant: can never change
    var count: u32 = 0; // variable: can change; type written out
    count += 1;
    count += 1;

    const ratio: f64 = 0.75; // a type annotation on a const is fine too
    const name = "seek"; // type inferred from the literal

    std.debug.print("answer={d} count={d} ratio={d} name={s}\n", .{ answer, count, ratio, name });
}
