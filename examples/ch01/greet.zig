//! A tiny module. This whole file is a struct with three declarations.
const std = @import("std");

/// Public: other files can use `greet.greeting`.
pub const greeting = "Hello";

/// Public function.
pub fn shout(times: u32) u32 {
    return times * volume;
}

// Private: visible only inside this file.
const volume = 10;

test "shout multiplies by the volume" {
    try std.testing.expect(shout(3) == 30);
}
