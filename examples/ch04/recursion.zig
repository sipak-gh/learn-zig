const std = @import("std");

fn factorial(n: u64) u64 {
    if (n <= 1) return 1;
    return n * factorial(n - 1);
}

// Greatest common divisor, Euclid's way.
fn gcd(a: u64, b: u64) u64 {
    return if (b == 0) a else gcd(b, a % b);
}

pub fn main() void {
    std.debug.print("10! = {d}\n", .{factorial(10)});
    std.debug.print("gcd(48, 36) = {d}\n", .{gcd(48, 36)});
}
