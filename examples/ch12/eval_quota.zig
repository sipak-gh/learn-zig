const std = @import("std");

/// The first `n` prime numbers, computed by trial division.
fn primes(comptime n: usize) [n]u32 {
    // The default limit is 1000 backward branches (loop iterations and
    // recursive calls) per comptime evaluation. This needs more.
    @setEvalBranchQuota(100_000);
    var result: [n]u32 = undefined;
    var count: usize = 0;
    var candidate: u32 = 2;
    while (count < n) : (candidate += 1) {
        var d: u32 = 2;
        const is_prime = while (d * d <= candidate) : (d += 1) {
            if (candidate % d == 0) break false;
        } else true;
        if (is_prime) {
            result[count] = candidate;
            count += 1;
        }
    }
    return result;
}

// Computed while compiling; the binary just contains 500 numbers.
const table = primes(500);

pub fn main() void {
    std.debug.print("first: {any}\n", .{table[0..10]});
    std.debug.print("500th prime: {d}\n", .{table[499]});
}
