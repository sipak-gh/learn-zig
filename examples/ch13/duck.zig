const std = @import("std");

const Dog = struct {
    name: []const u8,
    pub fn speak(self: Dog) []const u8 {
        _ = self;
        return "woof";
    }
};

const Robot = struct {
    id: u32,
    pub fn speak(self: Robot) []const u8 {
        return if (self.id % 2 == 0) "beep" else "boop";
    }
};

/// Accepts any value with a `speak` method that returns a string.
fn introduce(thing: anytype) void {
    std.debug.print("{s} says {s}\n", .{ @typeName(@TypeOf(thing)), thing.speak() });
}

pub fn main() void {
    introduce(Dog{ .name = "Rex" });
    introduce(Robot{ .id = 7 });
}
