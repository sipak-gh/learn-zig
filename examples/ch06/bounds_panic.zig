const std = @import("std");

pub fn main() void {
    const letters = [_]u8{ 'a', 'b', 'c' };
    var i: usize = 0;
    // Bug: `<=` walks one step past the end.
    while (i <= letters.len) : (i += 1) {
        std.debug.print("{c}\n", .{letters[i]});
    }
}
